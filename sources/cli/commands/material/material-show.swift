import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialShowAbstract), discussion: String(localized: .materialShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .materialShowHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            if g.json {
                let text = m.isText ? try? c.store.readText(m.path) : nil
                return try printJSON(ShownMaterial(material: m, text: text))
            }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(m.path.link(c.store.url.appending(path: m.path)).styled(.bold))
            say(String(localized: .materialShowRole(m.role?.rawValue ?? "-")))
            if let format = m.format { say(String(localized: .materialShowFormat(ShownMaterial.label(format)))) }
            say(String(localized: .materialShowStatus(m.status.rawValue.toned)))
            let sessions = f.sessionLinks(of: m.id)
            if !sessions.isEmpty {
                say(String(localized: .materialShowSessions))
                for (s, link) in sessions {
                    let pages = link.firstPage.map { first in " p.\(first)\(link.lastPage.map { "-\($0)" } ?? "")" } ?? ""
                    say("    \(f.reference(of: s, calendar: r.ctx.calendar))\(pages)")
                }
            }
            let units = m.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
            if !units.isEmpty {
                say(String(localized: .materialShowUnits))
                for u in units { say("    \(u)") }
            }
        }
    }
}
