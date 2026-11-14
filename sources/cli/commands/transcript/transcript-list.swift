import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension TranscriptCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .transcriptListAbstract), discussion: String(localized: .transcriptListDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let r = Resolver(try CLI.context(g))
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: r.semesters)
            if g.json { return try printJSON(rows) }
            TranscriptCommand.print(rows, semester: true)
        }
    }
}
