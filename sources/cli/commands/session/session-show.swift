import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension SessionCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .sessionShowAbstract), discussion: String(localized: .sessionShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionShowHelpSession), valueName: "session"), completion: Complete.sessions)
        var session: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(session)
            let s = try r.session(name, in: c)
            if g.json { return try printJSON(s) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(f.title(of: s, calendar: r.ctx.calendar).styled(.bold))
            say(String(localized: .sessionShowDate(when(s.date, now: r.ctx.now, time: true))))
            switch s.kind {
            case .cancelled: say(String(localized: .sessionShowCancelled))
            case .makeup: say(String(localized: .sessionShowMakeup))
            case .lecture: break
            }
            if let end = s.end(schedule: f.course.schedule, calendar: r.ctx.calendar) {
                say(String(localized: .sessionShowEnd(end.formatted(date: .omitted, time: .shortened))))
            }
            if let link = s.link(schedule: f.course.schedule, calendar: r.ctx.calendar) {
                say(String(localized: .sessionShowLink(link.absoluteString)))
            }
            let units = s.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
            if !units.isEmpty {
                say(String(localized: .sessionShowUnits))
                for u in units { say("    \(u)") }
            }
            let materials = s.materials.compactMap { link in f.materials.first { $0.id == link.materialId }.map { ($0, link) } }
            if !materials.isEmpty {
                say(String(localized: .sessionShowMaterials))
                for (m, link) in materials {
                    let pages = link.pages.map { " p.\($0.lowerBound)\($0.count > 1 ? "-\($0.upperBound)" : "")" } ?? ""
                    say("    \((m.path as NSString).lastPathComponent)\(pages)")
                }
            }
        }
    }
}
