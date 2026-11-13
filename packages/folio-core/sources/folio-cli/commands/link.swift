import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension AppLink.Kind: ExpressibleByArgument {}

/// What `folio link` and `folio open` point at: a kind and the item, named as every other command names it.
struct LinkTarget: ParsableArguments {
    @Argument(help: ArgumentHelp(String(localized: .linkHelpKind), valueName: "kind")) var kind: AppLink.Kind
    @Argument(help: ArgumentHelp(String(localized: .linkHelpRef), valueName: "ref")) var ref: String = ""
    @Option(help: ArgumentHelp(String(localized: .linkHelpPage), valueName: "n")) var page: Int?
    @Option(help: ArgumentHelp(String(localized: .linkHelpHeading), valueName: "heading")) var heading: String?
    @Option(help: ArgumentHelp(String(localized: .linkHelpBlock), valueName: "id")) var block: String?
    @Option(help: ArgumentHelp(String(localized: .linkHelpTime), valueName: "m:ss")) var time: String?
    // A string, not an enum: which names it takes depends on the kind, a course's pages or settings' tabs.
    @Option(help: ArgumentHelp(String(localized: .linkHelpSection), valueName: "page")) var section: String?

    struct Resolved: Encodable {
        var link: String
        var kind: String
        var id: UUID?
        var title: String
    }

    func resolve(_ r: Resolver) throws -> Resolved {
        if page != nil, !kind.anchors.contains(.page) { throw usage(.linkPageOnlyMaterial) }
        if heading != nil, !kind.anchors.contains(.heading) { throw usage(.linkAnchorOnlyNote) }
        if block != nil, !kind.anchors.contains(.block) { throw usage(.linkAnchorOnlyNote) }
        if time != nil, !kind.anchors.contains(.time) { throw usage(.linkTimeOnlyRecording) }
        if section != nil, !kind.hasPages { throw usage(.linkSectionOnlyCourse) }
        if kind.isPlace, !ref.isEmpty { throw usage(.linkPlaceTakesNoRef(kind.rawValue)) }
        // No default: one sent every kind it didn't name to the note lookup, which then printed a link of the new kind
        // carrying a note's ID.
        switch kind {
        case .today, .grades, .requirements, .people, .codes, .whatsNew, .proposals:
            return done(.place(kind), title: kind.rawValue)
        case .settings:
            return done(.settings(try page(AppLink.SettingsPage.self)), title: section ?? kind.rawValue)
        case .semester:
            let s = try r.semester(ref.isEmpty ? nil : ref)
            return done(AppLink(.semester, s.id), title: s.folder?.name ?? s.source ?? s.id.uuidString)
        case .course:
            let c = try r.course(ref)
            return done(.course(c.id, page: try page(AppLink.CoursePage.self)), title: "\(c.code) \(c.course.title)")
        case .person:
            let p = try r.person(ref)
            return done(AppLink(.person, p.id), title: p.name)
        case .card:
            return try card(r)
        case .session:
            return try item(r) { c, name in let s = try r.session(name, in: c); return (s.id, c.file.title(of: s, calendar: r.ctx.calendar)) }
        case .unit:
            return try item(r) { c, name in let u = try r.unit(name, in: c); return (u.id, u.title) }
        case .exam:
            return try item(r) { c, name in let e = try r.exam(name, in: c); return (e.id, e.title) }
        case .assignment:
            return try item(r) { c, name in let a = try r.assignment(name, in: c); return (a.id, a.title) }
        case .problemSet:
            return try item(r) { c, name in let p = try r.problemSet(name, in: c); return (p.id, p.title) }
        case .material:
            return try item(r) { c, name in let m = try r.material(name, in: c); return (m.id, m.path) }
        case .note:
            return try item(r) { c, name in try note(r, name, in: c) }
        case .recording:
            return try item(r) { c, name in let rec = try r.recording(name, in: c); return (rec.id, (rec.file as NSString).lastPathComponent) }
        }
    }

    /// Something a course holds, named `<course>/<name>`.
    func item(_ r: Resolver, find: (CourseRef, String) throws -> (UUID, String)) throws -> Resolved {
        let (c, name) = try r.split(ref)
        let (id, title) = try find(c, name)
        let anchor: AppLink.Anchor? = try page.map { .page($0) } ?? block.map { .block($0) } ?? heading.map { .heading($0) } ?? time.map(moment)
        let link = AppLink(kind, id, anchor: anchor)
        if anchor != nil, link.anchor == nil { throw usage(.linkBadAnchor) }
        return done(link, title: "\(c.code)/\(title)")
    }

    /// Read as the address reads it, so `--time 12:30` and `#t=12:30` name the same moment.
    func moment(_ written: String) throws -> AppLink.Anchor {
        guard let link = AppLink(string: "folio://recording/\(UUID().uuidString)#t=\(written)"), let anchor = link.anchor else {
            throw usage(.linkBadTime(written))
        }
        return anchor
    }

    func note(_ r: Resolver, _ name: String, in c: CourseRef) throws -> (UUID, String) {
        let file = try r.note(name, in: c)
        let path = c.store.coursePath(of: file.url) ?? file.url.lastPathComponent
        guard let id = file.meta.id else {
            throw CLIError(exit: .notFound, message: String(localized: .linkNoteWithoutId(path)),
                           hints: ["folio note adopt \(c.code) \"\(path)\""])
        }
        return (id, file.title)
    }

    /// Cards have no names to speak of (a prompt is a sentence), so one is named by its ID, as `quiz list` prints it.
    func card(_ r: Resolver) throws -> Resolved {
        let (c, rest): (CourseRef?, String) = ref.contains("/") ? try r.split(ref) : (nil, ref)
        guard let id = UUID(uuidString: rest) else { throw usage(.linkCardNeedsId) }
        for course in c.map({ [$0] }) ?? r.courses {
            for unit in course.file.units {
                if let card = try? course.store.loadQuiz(unit: unit.id).model.cards.first(where: { $0.id == id }) {
                    return done(AppLink(.card, card.id), title: "\(course.code)/\(card.prompt)")
                }
            }
        }
        throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("카드", rest)))
    }

    func page<Page: RawRepresentable & CaseIterable>(_: Page.Type) throws -> Page? where Page.RawValue == String {
        guard let section else { return nil }
        guard let page = Page(rawValue: section.lowercased()) else {
            throw usage(.linkBadSection(section, Page.allCases.map(\.rawValue).joined(separator: ", ")))
        }
        return page
    }

    func done(_ link: AppLink, title: String) -> Resolved {
        Resolved(link: link.string, kind: link.kind.rawValue, id: link.id, title: title)
    }

    func usage(_ message: LocalizedStringResource) -> CLIError {
        CLIError(exit: .usage, message: String(localized: message))
    }
}

struct LinkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "link", abstract: String(localized: .linkAbstract), discussion: String(localized: .linkDiscussion))
    @OptionGroup var g: GlobalOptions
    @OptionGroup var target: LinkTarget

    func run() throws {
        let resolved = try target.resolve(Resolver(try CLI.context(g)))
        if g.json { return try printJSON(resolved) }
        say(resolved.link)
    }
}

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "open", abstract: String(localized: .openAbstract), discussion: String(localized: .openDiscussion))
    @OptionGroup var g: GlobalOptions
    @OptionGroup var target: LinkTarget

    func run() throws {
        let resolved = try target.resolve(Resolver(try CLI.context(g)))
        // Tests and dry runs only print it: an app window opening under `swift test` would take the user's focus.
        if !g.dryRun, CLI.overrides == nil {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/open")
            // The URL form: a block's `^` isn't valid in a URL, and the app reads it back escaped (`AppLink(url:)`).
            p.arguments = [AppLink(string: resolved.link)?.url.absoluteString ?? resolved.link]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw CLIError(exit: .unexpected, message: String(localized: .openFailed(resolved.link))) }
        }
        if g.json { return try printJSON(resolved) }
        say(resolved.link)
    }
}
