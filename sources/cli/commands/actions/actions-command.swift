import ArgumentParser
import FolioActions
import Foundation

struct ActionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "actions", abstract: String(localized: .actionsAbstract),
        discussion: String(localized: .actionsDiscussion))

    @OptionGroup var g: GlobalOptions
    @Flag(help: ArgumentHelp(String(localized: .actionsHelpCheck))) var check = false
    @Flag(help: ArgumentHelp(String(localized: .actionsHelpSchema))) var schema = false

    struct Row: Encodable {
        var action: String
        var command: String
        var hasCommand: Bool
        var generated: Bool
        var manualReason: String?
        var screens: [String]
        var equivalenceTest: Bool
    }

    struct Report: Encodable {
        var actions: [Row]
        var directWrites: [String]
        var passed: Bool
    }

    func run() throws {
        if schema { return try printJSON(actionSchemas()) }
        let repo = try Self.repository()
        let commands = Set(Self.commandPaths(Folio.self))
        let app = Self.sources(repo.appending(path: "app"))
        let tests = Self.sources(repo.appending(path: "tests/unit/cli")).map(\.1).joined()
        let rows = Actions.all.map { type in
            let name = String(describing: type)
            let call = "\(name)("
            let path = type.command.components(separatedBy: " --")[0]
            return Row(
                action: name, command: type.command, hasCommand: commands.contains(path),
                generated: type.spec.generated, manualReason: type.spec.manualReason,
                screens: app.filter { $0.1.contains(call) }.map { ($0.0 as NSString).deletingPathExtension },
                equivalenceTest: tests.contains(call))
        }
        let writes = Self.directWrites(app)
        let unexplained = rows.filter { !$0.generated && ($0.manualReason ?? "").isEmpty }
        let unexplainedReads =
            Queries.all.filter { !$0.spec.generated && ($0.spec.manualReason ?? "").isEmpty }.map { $0.spec.command }
            + Self.unexplainedHandReads()
        let commandless = Queries.all.map { $0.spec.command }.filter { !commands.contains($0) }
        let passed =
            rows.allSatisfy { $0.hasCommand && $0.equivalenceTest } && writes.isEmpty && unexplained.isEmpty && unexplainedReads.isEmpty
            && commandless.isEmpty
        if g.json {
            try printJSON(Report(actions: rows, directWrites: writes, passed: passed))
        } else {
            var t = Table(
                header: [
                    String(localized: .actionsHeaderAction), String(localized: .actionsHeaderCommand),
                    String(localized: .actionsHeaderScreens), String(localized: .actionsHeaderEquivalence),
                ], shrink: [2])
            for r in rows {
                t.rows.append([
                    r.action, r.hasCommand ? r.command : String(localized: .actionsNoCommand).styled(.red),
                    r.screens.isEmpty ? String(localized: .actionsCliOnly).styled(.dim) : r.screens.joined(separator: ", "),
                    r.equivalenceTest ? "✓".styled(.green) : "✗".styled(.red),
                ])
            }
            t.print()
            for w in writes { say("✗".styled(.red) + " " + String(localized: .actionsDirectWrite(w))) }
            for r in unexplained { say("✗".styled(.red) + " " + String(localized: .actionsNoReason(r.command))) }
            for q in unexplainedReads { say("✗".styled(.red) + " " + String(localized: .actionsNoReadReason(q))) }
            for q in commandless { say("✗".styled(.red) + " " + String(localized: .actionsQueryNoCommand(q))) }
            let n = rows.count
            say(
                [
                    String(localized: .actionsSummaryActions(n)),
                    String(localized: .actionsSummaryCommands(rows.filter(\.hasCommand).count, n)),
                    String(localized: .actionsSummaryGenerated(rows.filter(\.generated).count, n)),
                    String(localized: .actionsSummaryTests(rows.filter(\.equivalenceTest).count, n)),
                    String(localized: .actionsSummaryWrites(writes.count)),
                ].joined(separator: " · ").styled(.dim))
        }
        if check, !passed { throw ExitCode(Exit.coverage.rawValue) }
    }

    static func repository() throws -> URL {
        let marker = "sources/cli/generated/generated-commands.swift"
        for start in [URL(filePath: FileManager.default.currentDirectoryPath), URL(filePath: #filePath)] {
            var dir = start
            while dir.path != "/" {
                if FileManager.default.fileExists(atPath: dir.appending(path: marker).path) { return dir }
                dir.deleteLastPathComponent()
            }
        }
        throw CLIError(exit: .usage, message: String(localized: .actionsOutsideRepo))
    }

    static func commandPaths(_ type: ParsableCommand.Type, prefix: [String] = []) -> [String] {
        let config = type.configuration
        let subs = config.subcommands + config.groupedSubcommands.flatMap(\.subcommands)
        return subs.flatMap { sub in
            let name = sub.configuration.commandName ?? sub._commandName
            let path = prefix + [name]
            return [path.joined(separator: " ")] + commandPaths(sub, prefix: path)
        }
    }

    // 손으로 짠 끝 명령 중 액션도, 읽기 선언도, 액션을 만드는 명령도, MCP 도구가 아닌 명령도 아닌 것은 손 읽기 명령이고
    // 이유(`HandRead.reason`)가 있어야 한다.
    static func unexplainedHandReads() -> [String] {
        let declared = Set(Actions.all.map { $0.command.components(separatedBy: " --")[0] } + Queries.all.map { $0.spec.command })
        return MCPServer.commands.compactMap { path, type in
            let config = type.configuration
            guard !path.isEmpty, config.subcommands.isEmpty, config.groupedSubcommands.isEmpty, !declared.contains(path),
                !String(reflecting: type).contains(".GeneratedCommands."), !(type is any BuildsAction.Type),
                !MCPServer.notTools.contains(path), !MCPServer.notTools.contains(String(path.split(separator: " ")[0]))
            else { return nil }
            return ((type as? any HandRead.Type)?.reason ?? "").isEmpty ? path : nil
        }.sorted()
    }

    static func sources(_ root: URL) -> [(String, String)] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url.lastPathComponent, $0) }
        }
    }

    nonisolated(unsafe) static let writePattern =
        #/\.save\(|\.write\(to:|\.log\.append\(|MoveJournal\.(apply|undo)|FileManager\.default\.(createDirectory|moveItem|removeItem|copyItem|trashItem|createFile)|\.trashNote\(|\.ensureID\(/#

    static func directWrites(_ files: [(String, String)]) -> [String] {
        files.flatMap { name, text in
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.indices.compactMap { i -> String? in
                guard lines[i].contains(writePattern) else { return nil }
                let marked = [lines[i], i > 0 ? lines[i - 1] : ""].contains { $0.contains("folio:not-an-action") }
                return marked ? nil : "\(name):\(i + 1)"
            }
        }
    }
}
