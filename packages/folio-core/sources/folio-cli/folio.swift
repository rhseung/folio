import ArgumentParser
import Foundation

struct Folio: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folio",
        abstract: String(localized: .folioAbstract),
        groupedSubcommands: [
            CommandGroup(name: String(localized: .folioGroupToday), subcommands: [TodayCommand.self]),
            CommandGroup(name: String(localized: .folioGroupClass), subcommands: [SessionCommand.self, UnitCommand.self, AttendanceCommand.self]),
            CommandGroup(name: String(localized: .folioGroupExams), subcommands: [ExamCommand.self, AssignmentCommand.self]),
            CommandGroup(name: String(localized: .folioGroupGrades), subcommands: [ScoreCommand.self, ComponentCommand.self, TranscriptCommand.self, RequirementCommand.self, GPACommand.self, UnlockCommand.self, LockCommand.self]),
            CommandGroup(name: String(localized: .folioGroupStudy), subcommands: [ReviewCommand.self, QuizCommand.self, ProblemSetCommand.self]),
            CommandGroup(name: String(localized: .folioGroupMaterials), subcommands: [MaterialCommand.self, NoteCommand.self, SearchCommand.self]),
            CommandGroup(name: String(localized: .folioGroupSetup), subcommands: [SemesterCommand.self, CourseCommand.self, CatalogCommand.self, SettingsCommand.self]),
            CommandGroup(name: String(localized: .folioGroupTools), subcommands: [ImportCommand.self, CheckCommand.self, CleanupCommand.self, BackupCommand.self, ActionsCommand.self, RunCommand.self, MCPCommand.self, SkillCommand.self, CompletionCommand.self]),
        ]
    )

    /// Below the command list, as docs/SPEC.md "도움말" asks; ArgumentParser would put a discussion above it.
    static let footer = String(localized: .folioFooter)

    /// ArgumentParser's help labels are English and fixed; these sit at line starts or in parentheses, so columns stay aligned.
    static func korean(_ help: String) -> String {
        [("OVERVIEW: ", ""), ("USAGE: ", String(localized: .helpLabelUsage)), ("ARGUMENTS:", String(localized: .helpLabelArguments)), ("OPTIONS:", String(localized: .helpLabelOptions)), (" SUBCOMMANDS:", ":"),
         ("SUBCOMMANDS:", String(localized: .helpLabelSubcommands)), ("Show help information.", String(localized: .helpLabelShowHelp)), ("(values: ", String(localized: .helpLabelValues)), ("default: ", String(localized: .helpLabelDefault)),
         ("See 'folio help <subcommand>' for detailed help.", String(localized: .helpLabelSeeSubcommand))]
            .reduce(help) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Only the start of a line changes, so columns still line up.
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
            if indent.isEmpty, body.hasSuffix(":") || body.hasPrefix(String(localized: .helpLabelUsage)), let colon = body.firstIndex(of: ":") {
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

    /// Tests call this in-process.
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
            return CLIError(exit: .usage, message: String(localized: .folioUnknownCommand(here, arg)),
                            hints: near.map { [String(localized: .folioDidYouMean(here, $0.0))] } ?? ["\(here) --help"])
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

/// The `folio` binary's entry point.
public func folioMain() { Folio.main() }
