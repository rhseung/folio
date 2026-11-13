import ArgumentParser
import FolioDomain
import Foundation

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: String(localized: .checkAbstract),
        discussion: String(localized: .checkDiscussion))

    @OptionGroup var g: GlobalOptions

    struct Issue: Encodable {
        var kind: String
        var path: String
    }

    func run() throws {
        let issues = try CLI.gist(g).layoutIssues().map { Issue(kind: String(describing: $0.kind), path: $0.path) }
        if g.json {
            try printJSON(issues)
        } else if issues.isEmpty {
            say("✓".styled(.green) + " " + String(localized: .checkOk))
        } else {
            var t = Table(header: [String(localized: .checkHeaderKind), String(localized: .checkHeaderPath)])
            t.rows = issues.map { [$0.kind, $0.path] }
            t.print()
        }
        if !issues.isEmpty { throw CLIError(exit: .rule, message: String(localized: .checkIssues(issues.count))) }
    }
}
