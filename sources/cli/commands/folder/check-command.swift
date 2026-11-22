import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct CheckCommand: ParsableCommand, HandRead {

    static let reason = "문제를 모두 보인 뒤 규칙 오류로 끝난다"
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: String(localized: .checkAbstract),
        discussion: String(localized: .checkDiscussion))

    @OptionGroup var g: GlobalOptions

    struct Issue: Encodable {
        var kind: String
        var path: String
    }

    func run() throws {
        var issues = try CLI.gist(g).layoutIssues().map { Issue(kind: String(describing: $0.kind), path: $0.path) }
        // 비어 있는 연결은 계산이나 사용자가 채울 빈자리라서 `course gaps`가 보이고, 틀린 곳을 가리키는 연결만 여기서 문제로 본다.
        let ctx = ReadContext(try CLI.context(g))
        for c in ctx.courses() {
            for gap in c.file.linkGaps(now: ctx.now, today: ctx.today, calendar: ctx.calendar) where gap.isDangling {
                let path = c.store.url.lastPathComponent + ": " + c.file.describe(gap, calendar: ctx.calendar)
                issues.append(Issue(kind: "danglingLink", path: path))  // strings: data, JSON의 종류 이름
            }
        }
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
