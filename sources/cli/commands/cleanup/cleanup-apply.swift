import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CleanupCommand {
    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .cleanupApplyAbstract), discussion: String(localized: .cleanupApplyDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .cleanupApplyHelpPlan), valueName: "file"), completion: .file()) var plan: String
        @Option(help: ArgumentHelp(String(localized: .cleanupApplyHelpBackup), valueName: "folder"), completion: .directory) var backup:
            String
        @Flag(help: ArgumentHelp(String(localized: .cleanupApplyHelpIncludeFlagged))) var includeFlagged = false

        func run() throws {
            let ctx = try CLI.context(g)
            let file = try StoredDocument<CleanupPlan>.read(from: URL(filePath: absolute(plan))).model
            let moves = includeFlagged ? file.moves : file.moves.filter { $0.review == nil }
            if !g.dryRun {
                try ask(String(localized: .cleanupApplyConfirm(moves.count)), g)
                let copy = try ctx.gist.backup(into: URL(filePath: absolute(backup)), now: ctx.now)
                if !g.json { say(String(localized: .cleanupApplyBackup(copy.path)).styled(.dim)) }
            }
            var options = g
            options.yes = true
            try perform(spec: CleanupApply(moves: moves, removals: file.removals), options, ctx: ctx)
        }
    }
}
