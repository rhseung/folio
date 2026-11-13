import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

/// A picture or widget file as `show --json` reports it, with the hash its `write --expect` compares.
struct NoteFileBody: Encodable {
    var name: String
    var path: String
    var text: String
    var hash: String
}

struct NoteFileItem: Encodable {
    var name: String
    var path: String
    var size: Int
    var modified: Date?
    /// Notes whose text names the file, by course-relative path.
    var notes: [String]
}

extension NoteCommand {
    struct Format: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteFormatAbstract))
        @OptionGroup var g: GlobalOptions

        func run() throws { say(NoteWritingGuide.text) }
    }

    struct Figure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteFigureAbstract), subcommands: [List.self, Show.self, Render.self] + GeneratedCommands.noteFigure)

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteFigureListAbstract))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""

            func run() throws {
                let r = Resolver(try CLI.context(g))
                let c = try r.course(course)
                let names = (try? FileManager.default.contentsOfDirectory(atPath: c.store.fileURL(NoteFigure.folder).path)) ?? []
                let files = names.filter { $0.lowercased().hasSuffix(".svg") }.sorted()
                try listFiles(c, files.map { ($0, NoteFigure.path($0)) }, json: g.json)
            }
        }

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteFigureShowAbstract))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String
            @Argument(help: ArgumentHelp(String(localized: .noteFigureHelpName), valueName: "name")) var name: String

            func run() throws {
                let c = try Resolver(try CLI.context(g)).course(course)
                let (file, text) = try readFigure(c, name)
                if g.json { return try printJSON(NoteFileBody(name: file, path: NoteFigure.path(file), text: text, hash: contentHash(text))) }
                say(text)
            }
        }

        struct Render: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteFigureRenderAbstract), discussion: String(localized: .noteRenderDiscussion))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .noteRenderHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
            @Argument(help: ArgumentHelp(String(localized: .noteFigureHelpName), valueName: "name")) var name: String?
            @Option(help: ArgumentHelp(String(localized: .noteFigureRenderHelpText), valueName: "svg")) var text: String?
            @Option(help: ArgumentHelp(String(localized: .noteFigureRenderHelpFile), valueName: "file"), completion: .file()) var svg: String?
            @OptionGroup var out: RenderOutput

            func run() throws {
                let r = Resolver(try CLI.context(g))
                let c = try course.isEmpty && (text != nil || svg != nil) ? nil : r.course(course)
                let source: (label: String, text: String)
                if let text {
                    source = ("figure", text)
                } else if let svg {
                    source = (URL(filePath: svg).deletingPathExtension().lastPathComponent, try readText(svg))
                } else {
                    guard let c, let name else { throw CLIError(exit: .usage, message: String(localized: .noteFigureRenderNothing)) }
                    let (file, read) = try readFigure(c, name)
                    source = ((file as NSString).deletingPathExtension, read)
                }
                try out.report(try PageRender.figure(source.text, accent: c?.color ?? CourseColor.neutral, widths: out.sizes), label: source.label, json: g.json)
            }
        }
    }

    struct Widget: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteWidgetAbstract), subcommands: [List.self, Show.self, Render.self] + GeneratedCommands.noteWidget)

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteWidgetListAbstract))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""

            func run() throws {
                let r = Resolver(try CLI.context(g))
                let c = try r.course(course)
                let folder = StandardLayout.metadataFolder + "/" + StandardLayout.widgetsFolder
                let names = (try? FileManager.default.contentsOfDirectory(atPath: c.store.fileURL(folder).path)) ?? []
                let ids = names.compactMap { n in n.hasSuffix(".html") ? UUID(uuidString: String(n.dropLast(5))) : nil }.map(\.uuidString).sorted()
                try listFiles(c, ids.map { ($0, NoteWidget.path(UUID(uuidString: $0)!)) }, json: g.json)
            }
        }

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteWidgetShowAbstract))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .noteWidgetHelpWidget), valueName: "widget")) var widget: String

            func run() throws {
                let r = Resolver(try CLI.context(g))
                let (c, ref) = try r.split(widget)
                let id = try r.widget(ref, in: c)
                let text = try MaterialText.read(c.store, NoteWidget.path(id))
                if g.json { return try printJSON(NoteFileBody(name: id.uuidString, path: NoteWidget.path(id), text: text, hash: contentHash(text))) }
                say(text)
            }
        }

        struct Render: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: String(localized: .noteWidgetRenderAbstract), discussion: String(localized: .noteRenderDiscussion))
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpWidget), valueName: "widget")) var widget: String = ""
            @Option(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpText), valueName: "html")) var text: String?
            @Option(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpFile), valueName: "file"), completion: .file()) var html: String?
            @OptionGroup var out: RenderOutput

            func run() throws {
                let r = Resolver(try CLI.context(g))
                let given = try text ?? html.map(readText)
                var course: CourseRef?
                var ref = ""
                // With the page given, the course alone names the accent.
                if given != nil, !widget.isEmpty, !widget.contains("/") {
                    course = try r.course(widget)
                } else if !widget.isEmpty || given == nil {
                    (course, ref) = try r.split(widget)
                }
                let source: (label: String, text: String)
                if let given {
                    source = (html.map { URL(filePath: $0).deletingPathExtension().lastPathComponent } ?? "widget", given)
                } else {
                    guard let c = course, !ref.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .noteWidgetRenderNothing)) }
                    let id = try r.widget(ref, in: c)
                    source = (String(id.uuidString.prefix(8)), try MaterialText.read(c.store, NoteWidget.path(id)))
                }
                try out.report(try PageRender.widget(source.text, accent: course?.color ?? CourseColor.neutral, widths: out.sizes), label: source.label, json: g.json)
            }
        }
    }
}

/// Where a render's pictures go when a person runs it; `--json` (and so `folio mcp`) carries them in the output.
struct RenderOutput: ParsableArguments {
    @Option(name: .customLong("width"), help: ArgumentHelp(String(localized: .noteRenderHelpWidth), valueName: "points")) var widths: [Int] = []
    @Option(help: ArgumentHelp(String(localized: .noteRenderHelpOut), valueName: "folder"), completion: .directory) var out: String?

    var sizes: [Int] { widths.isEmpty ? PageRender.widths : widths.map { min(max($0, 200), 1600) } }

    func report(_ result: RenderResult, label: String, json: Bool) throws {
        if json { return try printJSON(result) }
        let folder = URL(filePath: out.map(absolute) ?? FileManager.default.temporaryDirectory.appending(path: "folio-render").path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for shot in result.images {
            let url = folder.appending(path: "\(label)-\(shot.theme)-\(shot.width).png")
            try Data(base64Encoded: shot.png)?.write(to: url)
            say(url.path)
        }
        for p in result.problems { warn(p) }
        for line in result.console { warn(line) }
    }
}

/// Reads as `material write` does: only UTF-8 text.
enum MaterialText {
    static func read(_ store: CourseStore, _ path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw CLIError(exit: .notFound, message: String(localized: .noteFileMissing(path)))
        }
        do {
            return try store.readText(path)
        } catch StorageError.notUTF8 {
            throw CLIError(exit: .rule, message: String(localized: .noteFileNotUtf8(path)))
        }
    }
}

private func readFigure(_ c: CourseRef, _ name: String) throws -> (String, String) {
    guard let file = NoteFigure.fileName(name) else { throw CLIError(exit: .usage, message: String(localized: .noteFigureBadName(name))) }
    return (file, try MaterialText.read(c.store, NoteFigure.path(file)))
}

/// Which notes use each file: a picture by its file name, a widget by its id, as each appears in a note's text.
private func listFiles(_ c: CourseRef, _ files: [(name: String, path: String)], json: Bool) throws {
    let notes = (try? c.store.notes()) ?? []
    let texts = notes.compactMap { n in (try? c.store.read(n)).map { (c.store.coursePath(of: n.url) ?? n.url.lastPathComponent, $0) } }
    let items = files.map { f in
        let values = try? c.store.fileURL(f.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return NoteFileItem(name: f.name, path: f.path, size: values?.fileSize ?? 0, modified: values?.contentModificationDate,
                            notes: texts.filter { $0.1.contains(f.name) }.map(\.0))
    }
    if json { return try printJSON(items) }
    var t = Table(header: [String(localized: .noteFileHeaderName), String(localized: .noteFileHeaderNotes)], shrink: [1])
    for i in items { t.rows.append([i.name, i.notes.joined(separator: ", ")]) }
    t.print()
    footer(items.count)
}
