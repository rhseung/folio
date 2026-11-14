import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension UnitCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .unitListAbstract), discussion: String(localized: .unitListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .unitListHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .unitListHelpDepth), valueName: "depth")) var depth: Int?
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let outline = UnitTree.outline(f.units).filter { item in depth.map { item.depth < $0 } ?? true }
            if g.json { return try printJSON(outline.map(\.unit)) }
            if lines {
                for (u, _) in outline { line(["\(c.code)/\(u.title)", u.title, String(localized: .unitListSessions(u.sessionIds.count))]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            for (i, item) in outline.enumerated() {
                say(
                    treePrefix(outline.map(\.depth), at: i) + item.unit.title
                        + (item.unit.sessionIds.isEmpty
                            ? "" : String(localized: .unitListSessionsIndented(item.unit.sessionIds.count)).styled(.dim)))
            }
            footer(outline.count)
        }
    }
}
