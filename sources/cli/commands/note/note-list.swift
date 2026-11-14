import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteListAbstract), discussion: String(localized: .noteListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        struct Item: Encodable {
            var id: UUID?
            var path: String
            var kind: NoteKind
            var sessionId: UUID?
            var sessionIds: [UUID]
            var examId: UUID?
            var unitIds: [UUID]
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let store = c.store
            let notes = try store.notes()
            let path = { (n: NoteFile) in store.coursePath(of: n.url) ?? n.url.lastPathComponent }
            if g.json {
                return try printJSON(
                    notes.map {
                        Item(
                            id: $0.meta.id, path: path($0), kind: $0.meta.kind, sessionId: $0.meta.sessionId,
                            sessionIds: $0.meta.sessionIds, examId: $0.meta.examId, unitIds: $0.meta.unitIds)
                    })
            }
            let f = c.file
            let session = { (n: NoteFile) in f.sessionSpan(of: n.meta.id, calendar: r.ctx.calendar) ?? "" }
            if lines {
                for n in notes { line(["\(c.code)/\(path(n))", n.title, n.meta.kind.rawValue, session(n)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .noteListHeaderNote), String(localized: .noteListHeaderKind),
                    String(localized: .noteListHeaderSession), String(localized: .noteListHeaderPath),
                ], shrink: [3])
            for n in notes { t.rows.append([n.title, n.meta.kind.rawValue, session(n), path(n)]) }
            t.print()
            footer(notes.count)
        }
    }
}
