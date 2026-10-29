import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup", abstract: String(localized: .cleanupAbstract),
        subcommands: [Plan.self, Apply.self, Undo.self])

    static let reasonText: [ReviewReason: String] = [
        .guessedWeek: String(localized: .cleanupReasonGuessedWeek),
        .unknownWeek: String(localized: .cleanupReasonUnknownWeek),
        .guessedNumber: String(localized: .cleanupReasonGuessedNumber),
        .unknownNumber: String(localized: .cleanupReasonUnknownNumber),
        .guessedExam: String(localized: .cleanupReasonGuessedExam),
        .pastExamNameKept: String(localized: .cleanupReasonPastExamNameKept),
        .guessedFolder: String(localized: .cleanupReasonGuessedFolder),
        .unknownFile: String(localized: .cleanupReasonUnknownFile),
        .unknownFolder: String(localized: .cleanupReasonUnknownFolder),
        .nameCollision: String(localized: .cleanupReasonNameCollision),
    ]

    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .cleanupPlanAbstract), discussion: String(localized: .cleanupPlanDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .cleanupPlanHelpOut), valueName: "file"), completion: .file()) var out: String?
        @Option(help: ArgumentHelp(String(localized: .cleanupPlanHelpSkip), valueName: "path"), completion: .file(extensions: ["json"])) var skip: [String] = []

        func run() throws {
            let gist = try CLI.gist(g)
            let plan = CleanupPlanner.plan(try gist.readTree(), skip: Set(skip))
            if let out { try StoredDocument(new: plan).write(to: URL(filePath: absolute(out))) }
            if g.json { return try printJSON(plan) }
            say(String(localized: .cleanupPlanTitle).styled(.bold) + "  " + String(localized: .cleanupPlanSummary(plan.moves.count, plan.moves.filter { $0.review != nil }.count)).styled(.dim))
            // Grouped by destination: `<semester>/<course>` or `<semester>/_Admin`.
            let groups = Dictionary(grouping: plan.moves) { $0.to.split(separator: "/").prefix(2).joined(separator: "/") }
            for group in groups.keys.sorted() {
                let semester = group.split(separator: "/")[0]
                let rel = { (path: String) in
                    String(path.hasPrefix(group + "/") ? path.dropFirst(group.count + 1) : path.dropFirst(semester.count + 1))
                }
                say()
                say(group.styled(.bold))
                var t = Table(header: [String(localized: .cleanupPlanHeaderFrom), String(localized: .cleanupPlanHeaderTo), String(localized: .cleanupPlanHeaderReview)], shrink: [0, 1])
                for m in groups[group]!.sorted(by: { $0.from < $1.from }) {
                    t.rows.append([rel(m.from), rel(m.to), m.review.map { CleanupCommand.reasonText[$0]!.styled(.yellow) } ?? ""])
                }
                t.print()
            }
            if !plan.skipped.isEmpty {
                say()
                say(String(localized: .cleanupPlanSkipped).styled(.bold))
                for s in plan.skipped { say("  \(s)") }
            }
        }
    }

    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .cleanupApplyAbstract), discussion: String(localized: .cleanupApplyDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .cleanupApplyHelpPlan), valueName: "file"), completion: .file()) var plan: String
        @Option(help: ArgumentHelp(String(localized: .cleanupApplyHelpBackup), valueName: "folder"), completion: .directory) var backup: String
        @Flag(help: ArgumentHelp(String(localized: .cleanupApplyHelpIncludeFlagged))) var includeFlagged = false

        func run() throws {
            let ctx = try CLI.context(g)
            let file = try StoredDocument<CleanupPlan>.read(from: URL(filePath: absolute(plan))).model
            let moves = includeFlagged ? file.moves : file.moves.filter { $0.review == nil }
            if !g.dryRun {
                // Asked before the backup, so a declined run leaves no copy behind.
                try ask(String(localized: .cleanupApplyConfirm(moves.count)), g)
                let copy = try ctx.gist.backup(into: URL(filePath: absolute(backup)), now: ctx.now)
                if !g.json { say(String(localized: .cleanupApplyBackup(copy.path)).styled(.dim)) }
            }
            var options = g
            options.yes = true
            let result = try perform(spec: CleanupApply(moves: moves), options, ctx: ctx)
            if !g.json, let batch = result.made { say(String(localized: .cleanupApplyUndoHint(batch.uuidString)).styled(.dim)) }
        }
    }

    struct Undo: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .cleanupUndoAbstract), discussion: String(localized: .cleanupUndoDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .cleanupUndoHelpBatch), valueName: "batch"), completion: Complete.problemSets) var batch: UUID

        func run() throws {
            try perform(spec: CleanupUndo(batch: batch), g, ctx: try CLI.context(g))
        }
    }
}
