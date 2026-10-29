import ArgumentParser
import FolioDomain
import Foundation

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "GIST 폴더가 표준 구조를 따르는지 검사",
        discussion: """
            표준 구조와 다른 곳이 있으면 목록을 보여 주고 종료 코드 4로 끝난다. 없으면 0이다.

            예시:
              folio check
              folio check --json
            """)

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
            say("✓".styled(.green) + " 표준 구조를 따릅니다")
        } else {
            var t = Table(header: ["종류", "경로"])
            t.rows = issues.map { [$0.kind, $0.path] }
            t.print()
        }
        if !issues.isEmpty { throw CLIError(exit: .rule, message: "표준 구조와 다른 곳이 \(issues.count)개 있습니다") }
    }
}
