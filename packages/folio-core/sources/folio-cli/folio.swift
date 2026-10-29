import ArgumentParser
import Foundation

@main
struct Folio: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folio",
        abstract: "Folio의 GIST 폴더를 터미널에서 다룹니다. 앱과 같은 액션을 부릅니다.",
        groupedSubcommands: [
            CommandGroup(name: "오늘", subcommands: [TodayCommand.self]),
            CommandGroup(name: "수업", subcommands: [SessionCommand.self, UnitCommand.self, AttendanceCommand.self]),
            CommandGroup(name: "시험과 과제", subcommands: [ExamCommand.self, AssignmentCommand.self]),
            CommandGroup(name: "성적", subcommands: [ScoreCommand.self, ComponentCommand.self, TranscriptCommand.self, RequirementCommand.self, GPACommand.self, UnlockCommand.self, LockCommand.self]),
            CommandGroup(name: "복습과 퀴즈", subcommands: [ReviewCommand.self, QuizCommand.self, ProblemSetCommand.self]),
            CommandGroup(name: "자료와 노트", subcommands: [MaterialCommand.self, NoteCommand.self, SearchCommand.self]),
            CommandGroup(name: "설정과 카탈로그", subcommands: [SemesterCommand.self, CourseCommand.self, CatalogCommand.self, SettingsCommand.self]),
            CommandGroup(name: "가져오기와 점검", subcommands: [ImportCommand.self, CheckCommand.self, CleanupCommand.self, BackupCommand.self, ActionsCommand.self, RunCommand.self, SkillCommand.self, CompletionCommand.self]),
        ]
    )

    /// Below the command list, as docs/SPEC.md "도움말" asks; ArgumentParser would put a discussion above it.
    static let footer = """
        예시:
          folio today
          folio session list EC4207
          folio assignment add EC4207 "HW 4" --due "2026-11-11 23:59" --dry-run
          folio exam scope EC4207/Quiz1 --unit 트리 --dry-run
          folio search 매칭

        JSON으로 받으려면 --json, 쓰지 않고 보려면 --dry-run.
        명령 찾기: folio help 과제 마감 바꾸기
        개념 설명: folio help refs | output | exit | safety | fzf
        명령 목록을 기계가 읽게: folio help --json, folio actions --schema
        에이전트에게 쓰는 법 알려 주기: folio skill --install <스킬 폴더>
        """

    /// ArgumentParser's help labels are English and fixed; these sit at line starts or in parentheses, so columns stay aligned.
    static func korean(_ help: String) -> String {
        [("OVERVIEW: ", ""), ("USAGE: ", "사용법: "), ("ARGUMENTS:", "인자:"), ("OPTIONS:", "옵션:"), (" SUBCOMMANDS:", ":"),
         ("SUBCOMMANDS:", "명령:"), ("Show help information.", "도움말 보기"), ("(values: ", "(값: "), ("default: ", "기본값: "),
         ("See 'folio help <subcommand>' for detailed help.", "명령마다 자세한 도움말: folio <명령> --help")]
            .reduce(help) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Headings bold, example commands green, option names cyan. Only the start of a line changes, so columns still line up.
    static func colored(_ help: String) -> String {
        guard Style.enabled else { return help }
        return help.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let body = String(line.drop { $0 == " " })
            let indent = String(repeating: " ", count: line.count - body.count)
            // Splits at the first run of two or more spaces, where an option's or example's description starts.
            func split(_ s: String) -> (String, String) {
                guard let gap = s.firstMatch(of: /\s{2,}\S/) else { return (s, "") }
                return (String(s[..<gap.range.lowerBound]), String(s[gap.range.lowerBound...]))
            }
            if indent.isEmpty, body.hasSuffix(":") || body.hasPrefix("사용법:"), let colon = body.firstIndex(of: ":") {
                return String(body[...colon]).styled(.bold) + String(body[body.index(after: colon)...])
            }
            if body.hasPrefix("folio ") {
                let (command, note) = split(body)
                return indent + command.styled(.green) + note.styled(.dim)
            }
            if body.hasPrefix("-") {
                let (name, rest) = split(body)
                return indent + name.styled(.cyan) + rest
            }
            return line
        }.joined(separator: "\n")
    }

    static func main() {
        Darwin.exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    /// Parses and runs one command line, returning the exit code (docs/SPEC.md "출력"). Tests call this in-process.
    static func run(_ arguments: [String]) -> Int32 {
        let json = arguments.contains("--json")
        if arguments.first == "help", arguments.count == 2 {
            if arguments[1] == "--json" { return run(["--experimental-dump-help"]) }
            if let topic = Topic(arguments[1]) {
                topic.print()
                return Exit.success.rawValue
            }
        }
        // `folio help 과제 마감 바꾸기`: words that aren't a command name are a request to find one.
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if arguments.first == "help", let first = words.first, !first.hasPrefix("-"), Topic(first) == nil,
           !commandNames.contains(first) {
            do {
                try Finder.print(words.joined(separator: " "), json: json)
                return Exit.success.rawValue
            } catch let e as ExitCode {
                return e.rawValue
            } catch {
                report(CLIError(exit: .unexpected, message: String(describing: error)), json: json)
                return Exit.unexpected.rawValue
            }
        }
        do {
            var command = try parseAsRoot(arguments)
            try command.run()
            return Exit.success.rawValue
        } catch let e as CLIError {
            report(e, json: json)
            return e.exit.rawValue
        } catch let e as ExitCode {
            return e.rawValue
        } catch {
            let code = exitCode(for: error)
            if code == .success {
                let root = arguments.allSatisfy { $0.hasPrefix("-") || $0 == "help" }
                say(colored(korean(fullMessage(for: error))) + (root ? "\n\n" + footer : ""))
                return 0
            }
            if code == .validationFailure, let typo = unknownCommand(arguments) {
                report(typo, json: json)
                return typo.exit.rawValue
            }
            // ArgumentParser's own usage failures exit 64; the SPEC gives usage errors 2.
            let exit: Exit = code == .validationFailure ? .usage : Exit(rawValue: code.rawValue) ?? .unexpected
            report(CLIError(exit: exit, message: exit == .unexpected ? String(describing: error) : fullMessage(for: error)), json: json)
            return exit.rawValue
        }
    }

    static var commandNames: Set<String> {
        Set((configuration.subcommands + configuration.groupedSubcommands.flatMap { $0.subcommands }).map { $0._commandName })
    }

    /// `exam ad` → `exam add`. ArgumentParser blames whatever follows the typo (`Unknown option '--gist'`) and suggests nothing.
    static func unknownCommand(_ arguments: [String]) -> CLIError? {
        var command: ParsableCommand.Type = Folio.self
        var path = ["folio"]
        for arg in arguments where !arg.hasPrefix("-") && arg != "help" {
            // Closures, not key paths: key paths on these metatypes crash the compiler (SILGen).
            let subs = command.configuration.subcommands + command.configuration.groupedSubcommands.flatMap { $0.subcommands }
            guard !subs.isEmpty else { return nil }
            if let next = subs.first(where: { $0._commandName == arg }) {
                command = next
                path.append(arg)
                continue
            }
            // Insertions plus removals: a typo of one letter is 1, a swapped letter 2.
            let near = subs.map { s in (s._commandName, Array(s._commandName).difference(from: Array(arg)).count) }
                .filter { $0.1 <= 2 }.min { $0.1 < $1.1 }
            let here = path.joined(separator: " ")
            return CLIError(exit: .usage, message: "없는 명령입니다: \(here) \(arg)",
                            hints: near.map { ["혹시: \(here) \($0.0)"] } ?? ["\(here) --help"])
        }
        return nil
    }

    static func report(_ e: CLIError, json: Bool) {
        if json {
            struct Body: Encodable {
                struct Inner: Encodable { var code: String, message: String, candidates: [String] }
                var error: Inner
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(Body(error: .init(code: e.exit.code, message: e.message, candidates: e.candidates))) {
                warn(String(decoding: data, as: UTF8.self))
            }
            return
        }
        warn("✗".styled(.red) + " " + e.message)
        for c in e.candidates { warn("  " + c) }
        for h in e.hints { warn("  " + h.styled(.dim)) }
    }
}
