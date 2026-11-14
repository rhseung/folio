import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension UnitCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .unitShowAbstract), discussion: String(localized: .unitShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .unitShowHelpUnit), valueName: "unit"), completion: Complete.units) var unit:
            String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            if g.json { return try printJSON(u) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(u.title.styled(.bold))
            if let parent = u.parentId.flatMap({ id in f.units.first { $0.id == id } }) {
                say(String(localized: .unitShowParent(parent.title)))
            }
            let children = f.units.filter { $0.parentId == u.id }.sorted { $0.order < $1.order }
            for (title, names) in [
                (String(localized: .unitShowChildren), children.map(\.title)),
                (
                    String(localized: .unitShowSessions),
                    u.sessionIds.compactMap { id in f.sessions.first { $0.id == id }.map { f.reference(of: $0, calendar: r.ctx.calendar) } }
                ),
                (String(localized: .unitShowExams), u.examIds.compactMap { id in f.exams.first { $0.id == id }?.title }),
                (
                    String(localized: .unitShowPages),
                    u.lecturePages.compactMap { p in
                        f.materials.first { $0.id == p.materialId }.map {
                            "\(($0.path as NSString).lastPathComponent) p.\(p.firstPage)-\(p.lastPage)"
                        }
                    }
                ),
            ] where !names.isEmpty {
                say("  \(title)")
                for n in names { say("    \(n)") }
            }
        }
    }
}
