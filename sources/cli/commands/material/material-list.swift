import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialListAbstract), discussion: String(localized: .materialListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .materialListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let materials = f.materials.sorted { $0.path < $1.path }.filter { all || $0.status != .ignored }
            if g.json { return try printJSON(materials) }
            func sessions(_ m: Material) -> String {
                f.sessions.filter { s in s.materials.contains { $0.materialId == m.id } }.map {
                    f.reference(of: $0, calendar: r.ctx.calendar)
                }.joined(separator: ", ")
            }
            if lines {
                for m in materials { line(["\(c.code)/\(m.path)", m.role?.rawValue ?? "", m.status.rawValue, sessions(m)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .materialListHeaderPath), String(localized: .materialListHeaderRole),
                    String(localized: .materialListHeaderStatus), String(localized: .materialListHeaderSession),
                ], shrink: [3])
            for m in materials {
                t.rows.append([m.path, m.role?.rawValue ?? "", m.status.rawValue.toned, sessions(m)])
            }
            t.print()
            footer(materials.count, hidden: all ? nil : String(localized: .materialListHidden))
        }
    }
}
