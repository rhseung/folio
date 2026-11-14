import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CleanupCommand {
    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .cleanupPlanAbstract), discussion: String(localized: .cleanupPlanDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .cleanupPlanHelpOut), valueName: "file"), completion: .file()) var out: String?
        @Option(help: ArgumentHelp(String(localized: .cleanupPlanHelpSkip), valueName: "path"), completion: .file(extensions: ["json"]))
        var skip: [String] = []

        func run() throws {
            let gist = try CLI.gist(g)
            let plan = try gist.cleanupPlan(skip: Set(skip))
            if let out { try StoredDocument(new: plan).write(to: URL(filePath: absolute(out))) }
            if g.json { return try printJSON(plan) }
            say(
                String(localized: .cleanupPlanTitle).styled(.bold) + "  "
                    + String(localized: .cleanupPlanSummary(plan.moves.count, plan.moves.filter { $0.review != nil }.count)).styled(.dim))
            let groups = Dictionary(grouping: plan.moves) { $0.to.split(separator: "/").prefix(2).joined(separator: "/") }
            for group in groups.keys.sorted() {
                let semester = group.split(separator: "/")[0]
                let rel = { (path: String) in
                    String(path.hasPrefix(group + "/") ? path.dropFirst(group.count + 1) : path.dropFirst(semester.count + 1))
                }
                say()
                say(group.styled(.bold))
                var t = Table(
                    header: [
                        String(localized: .cleanupPlanHeaderFrom), String(localized: .cleanupPlanHeaderTo),
                        String(localized: .cleanupPlanHeaderLink), String(localized: .cleanupPlanHeaderReview),
                    ], shrink: [0, 1])
                for m in groups[group]!.sorted(by: { $0.from < $1.from }) {
                    t.rows.append([
                        rel(m.from), rel(m.to), CleanupCommand.link(m),
                        m.review.map { CleanupCommand.reasonText[$0]!.styled(.yellow) } ?? "",
                    ])
                }
                t.print()
            }
            if !plan.removals.isEmpty {
                say()
                say(String(localized: .cleanupPlanRemovals).styled(.bold))
                for r in plan.removals { say("  \(r)") }
            }
            if !plan.skipped.isEmpty {
                say()
                say(String(localized: .cleanupPlanSkipped).styled(.bold))
                for s in plan.skipped { say("  \(s)") }
            }
        }
    }
}
