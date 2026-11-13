import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialRole: ExpressibleByArgument {}
extension MaterialKind: ExpressibleByArgument {}

extension CourseRef {
    /// A second ref in the same course may be written with or without `<course>/` in front.
    func local(_ ref: String) -> String {
        ref.hasPrefix(code + "/") ? String(ref.dropFirst(code.count + 1)) : ref
    }
}

func absolute(_ path: String) -> String {
    URL(filePath: (path as NSString).expandingTildeInPath, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath + "/")).standardizedFileURL.path
}

struct MaterialCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "material", abstract: String(localized: .materialAbstract),
        subcommands: [List.self, Show.self, Read.self, Link.self, Relink.self, Import.self, Write.self, Split.self]
            + GeneratedCommands.material)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialListAbstract), discussion: String(localized: .materialListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .materialListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let materials = f.materials.sorted { $0.path < $1.path }.filter { all || $0.status != .ignored }
            if g.json { return try printJSON(materials) }
            func sessions(_ m: Material) -> String {
                f.sessions.filter { s in s.materials.contains { $0.materialId == m.id } }.map { f.reference(of: $0, calendar: r.ctx.calendar) }.joined(separator: ", ")
            }
            if lines {
                for m in materials { line(["\(c.code)/\(m.path)", m.role?.rawValue ?? "", m.status.rawValue, sessions(m)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .materialListHeaderPath), String(localized: .materialListHeaderRole), String(localized: .materialListHeaderStatus), String(localized: .materialListHeaderSession)], shrink: [3])
            for m in materials {
                t.rows.append([m.path, m.role?.rawValue ?? "", m.status.rawValue.toned, sessions(m)])
            }
            t.print()
            footer(materials.count, hidden: all ? nil : String(localized: .materialListHidden))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialShowAbstract), discussion: String(localized: .materialShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .materialShowHelpMaterial), valueName: "material"), completion: Complete.materials) var material: String = ""

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

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialLinkAbstract), discussion: String(localized: .materialLinkDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialLinkHelpSession), valueName: "session"), completion: Complete.sessions) var session: String = ""
        @Option(help: ArgumentHelp(String(localized: .materialLinkHelpPages), valueName: "pages")) var pages: String?
        @Flag(help: ArgumentHelp(String(localized: .materialLinkHelpOff))) var off = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let s = try r.session(c.local(session), in: c)
            let bounds = pages?.split(separator: "-").compactMap { Int($0) } ?? []
            guard pages == nil || (1...2).contains(bounds.count) else { throw CLIError(exit: .usage, message: String(localized: .materialLinkPagesFormat)) }
            try perform(spec: MaterialLinkSession(course: c.id, material: m.id, session: s.id, linked: !off, firstPage: bounds.first, lastPage: bounds.last),
                        g, ctx: ctx)
        }
    }

    struct Relink: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialRelinkAbstract), discussion: String(localized: .materialRelinkDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialRelinkHelpFile), valueName: "file"), completion: .file()) var file: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let path = file.hasPrefix("/") || file.hasPrefix("~") ? absolute(file) : c.store.url.appending(path: file).path
            try perform(spec: MaterialRelink(course: c.id, material: m.id, file: path), g, ctx: ctx)
        }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialWriteAbstract), discussion: String(localized: .materialWriteDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials) var material: String
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpFile), valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp(String(localized: .materialWriteHelpExpect), valueName: "hash")) var expect: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            var expected: String?
            if let expect, MaterialFormat(path: m.path).isText {
                let current = try c.store.readText(m.path)
                guard contentHash(current) == expect.lowercased() else {
                    throw CLIError(exit: .conflict, message: String(localized: .materialWriteConflict(m.path)),
                                   hints: [String(localized: .materialWriteConflictHint(c.code, m.path))])
                }
                // The action checks again right before writing, so a change between here and there is caught too.
                expected = current
            }
            try perform(spec: MaterialWrite(course: c.id, material: m.id, text: try readText(file), expected: expected), g, ctx: ctx)
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialImportAbstract), discussion: String(localized: .materialImportDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp(String(localized: .materialImportHelpFiles), valueName: "file"), completion: .file()) var files: [String]
        @Option(help: ArgumentHelp(String(localized: .materialImportHelpFolder), valueName: "folder"), completion: .directory) var folder: String
        @Option(help: ArgumentHelp(String(localized: .materialImportHelpSession), valueName: "session"), completion: Complete.sessions) var session: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let s = try session.map { try r.session(c.local($0), in: c).id }
            try perform(spec: MaterialImport(course: c.id, items: files.map { ImportItem(file: absolute($0), folder: folder, session: s) }), g, ctx: ctx)
        }
    }

    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .materialSplitAbstract), discussion: String(localized: .materialSplitDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialSplitHelpSections), valueName: "pages:unit")) var sections: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            // A title no unit has is a new unit; one new title written twice is the same new unit.
            var made: [String: UUID] = [:]
            let cuts = try sections.map { arg in
                // The first colon: the pages never hold one, a unit's title may.
                guard let colon = arg.firstIndex(of: ":") else { throw CLIError(exit: .usage, message: String(localized: .materialSplitFormat(arg))) }
                let bounds = arg[..<colon].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
                let title = String(arg[arg.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard (1...2).contains(bounds.count), let first = bounds.first ?? nil, let last = bounds.last ?? nil, !title.isEmpty else {
                    throw CLIError(exit: .usage, message: String(localized: .materialSplitFormat(arg)))
                }
                if let unit = c.file.units.first(where: { $0.title == title }) { return LectureCut(unit: unit.id, firstPage: first, lastPage: last) }
                let id = made[title] ?? UUID()
                made[title] = id
                return LectureCut(unit: id, title: title, firstPage: first, lastPage: last)
            }
            try perform(spec: MaterialSplit(course: c.id, material: m.id, sections: cuts), g, ctx: ctx)
        }
    }

}

/// A text material's JSON also carries the file as it is now and the hash `material write --expect` compares. The
/// material's own `hash` is from the last tracking, so after a change from another device it would never match.
struct ShownMaterial: Encodable {
    var material: Material
    var text: String?

    private enum Keys: String, CodingKey { case format, language, text, contentHash }

    func encode(to encoder: Encoder) throws {
        try material.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        if let format = material.format {
            try c.encode(format.name, forKey: .format)
            if case .code(let language) = format { try c.encode(language, forKey: .language) }
        }
        if let text {
            try c.encode(text, forKey: .text)
            try c.encode(contentHash(text), forKey: .contentHash)
        }
    }

    static func label(_ format: MaterialFormat) -> String {
        if case .code(let language) = format { return "\(format.name) (\(language))" }
        return format.name
    }
}
