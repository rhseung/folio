import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

// The panel's tools for reading what a course holds beyond its text files (#85): a PDF's pages, a recording's
// transcript, a note's pictures. Each read is capped (`ReadingLimit`) and says where the next one starts, as a tool's
// answer stays in the conversation for every later turn.

extension MaterialCommand {
    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialReadAbstract),
            discussion: String(
                localized: .materialReadDiscussion(ReadingLimit.pages, ReadingLimit.pageText, ReadingLimit.titles, ReadingLimit.images)))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String = ""
        @Option(help: ArgumentHelp(String(localized: .materialReadHelpPages), valueName: "pages")) var pages: String?
        @Flag(help: ArgumentHelp(String(localized: .materialReadHelpTitles))) var titles = false
        @Flag(help: ArgumentHelp(String(localized: .materialReadHelpImages(ReadingLimit.images)))) var images = false
        @Option(help: ArgumentHelp(String(localized: .picturesHelpOut), valueName: "folder"), completion: .directory) var out: String?

        struct Page: Encodable {
            var page: Int
            var title: String?
            /// Left out in `--titles`, where the words count says which pages are pictures more than text.
            var text: String?
            var words: Int
            var figures: Int
            /// Where its picture went: a file, or the name Claude got it under.
            var image: String?
        }

        struct Shown: Encodable {
            var path: String
            var pageCount: Int
            var first: Int
            var last: Int
            var outline: [Bookmark]?
            var pages: [Page]
            /// The `--pages` to pass to go on; nil once the asked pages are all read.
            var next: String?
        }

        struct Bookmark: Encodable {
            var title: String
            var page: Int
            var depth: Int
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            guard MaterialFormat(path: m.path) == .pdf else {
                throw CLIError(exit: .usage, message: String(localized: .materialReadNotPdf(m.path)))
            }
            guard let pdf = PDFPages.open(c.store.fileURL(m.path)) else {
                throw CLIError(exit: .notFound, message: String(localized: .materialReadUnreadable(m.path)))
            }

            let count = pdf.pageCount
            let given = try pages.map(Self.range)
            guard let asked = ReadingLimit.clamp(given, count: count) else {
                throw CLIError(exit: .usage, message: String(localized: .materialReadOutside(m.path, count)))
            }
            let most = images ? ReadingLimit.images : titles ? ReadingLimit.titles : ReadingLimit.pages
            let reach = ReadingLimit.served(asked, most: most)
            let read = reach.map { n in
                pdf.page(at: n - 1).map { PDFPages.text(of: $0, number: n) } ?? PDFPageText(page: n, text: "", words: 0, figures: 0)
            }
            let served =
                titles ? reach : ReadingLimit.served(asked, most: most, lengths: read.map(\.text.count), budget: ReadingLimit.pageText)
            let kept = read.prefix(served.count)

            let file = (m.path as NSString).lastPathComponent
            let pictures: [Pictures.Picture] =
                images
                ? kept.compactMap { p in
                    pdf.page(at: p.page - 1).flatMap { PDFPages.jpeg($0) }.map {
                        Pictures.Picture(label: "\(file) p.\(p.page)", file: "\(file) p\(p.page).jpg", data: $0)
                    }
                } : []
            let placed = try Pictures.hand(pictures, out: out, gist: r.ctx.gist.url)
            let placedAt = Dictionary(zip(pictures.map(\.label), placed), uniquingKeysWith: { a, _ in a })
            let next = ReadingLimit.next(after: served, asked: asked, most: most).map(Self.written)
            let shown = Shown(
                path: m.path, pageCount: count, first: served.lowerBound, last: served.upperBound,
                outline: titles ? PDFPages.outline(pdf).map { Bookmark(title: $0.title, page: $0.page, depth: $0.depth) } : nil,
                pages: kept.map { p in
                    Page(
                        page: p.page, title: p.title, text: titles ? nil : p.text, words: p.words, figures: p.figures,
                        image: placedAt["\(file) p.\(p.page)"] ?? nil)
                },
                next: next)
            if g.json { return try printJSON(shown) }

            say(String(localized: .materialReadHeader(m.path, count, served.lowerBound, served.upperBound)).styled(.bold))
            if let outline = shown.outline, !outline.isEmpty {
                say(String(localized: .materialReadOutline).styled(.dim))
                for b in outline { say(String(repeating: "  ", count: b.depth + 1) + "\(b.title)  " + "p.\(b.page)".styled(.dim)) }
            }
            for p in shown.pages {
                say(
                    "p.\(p.page)".styled(.cyan) + "  " + (p.title ?? "").styled(.bold)
                        + (titles ? "  " + String(localized: .materialReadWords(p.words)).styled(.dim) : ""))
                if let text = p.text { say(text.isEmpty ? String(localized: .materialReadNoText).styled(.dim) : text) }
                if let image = p.image { say("  → \(image)".styled(.dim)) }
            }
            if let next {
                var line = "folio material read \(Self.quoted("\(c.code)/\(m.path)")) --pages \(next)"
                if titles { line += " --titles" }
                if images { line += " --images" + (out.map { " --out \(Self.quoted($0))" } ?? "") }
                say(String(localized: .readingNext(line)).styled(.dim))
            }
        }

        /// `9`, `9-12`, `9-` (to the end).
        static func range(_ written: String) throws -> ClosedRange<Int> {
            guard let m = written.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\d{1,6})(?:(-)(\d{1,6})?)?/), let first = Int(m.1)
            else {
                throw CLIError(exit: .usage, message: String(localized: .materialReadPagesFormat(written)))
            }
            let last = m.3.flatMap { Int($0) } ?? (m.2 == nil ? first : Int.max)
            guard first >= 1, first <= last else {
                throw CLIError(exit: .usage, message: String(localized: .materialReadPagesFormat(written)))
            }
            return first...last
        }

        static func written(_ range: ClosedRange<Int>) -> String {
            range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
        }

        static func quoted(_ s: String) -> String { s.contains(" ") ? "\"\(s)\"" : s }
    }
}

extension RecordingCommand {
    struct Transcript: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .recordingTranscriptAbstract),
            discussion: String(localized: .recordingTranscriptDiscussion(ReadingLimit.transcript)))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .recordingTranscriptHelpRecording), valueName: "recording"), completion: Complete.sessions)
        var recording: String = ""
        @Option(help: ArgumentHelp(String(localized: .recordingTranscriptHelpFrom), valueName: "m:ss")) var from: String?
        @Option(help: ArgumentHelp(String(localized: .recordingTranscriptHelpTo), valueName: "m:ss")) var to: String?

        struct Line: Encodable {
            /// `12:30`: what `folio link recording … --time` takes, so an answer can point at the moment.
            var at: String
            var text: String
        }

        struct Shown: Encodable {
            var recording: String
            var session: String?
            var duration: String
            var lines: [Line]
            /// The `--from` to pass to go on; nil once the asked span is all read.
            var next: String?
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(recording)
            let rec = try r.recording(name, in: c)
            let start = try from.map(Self.seconds), end = try to.map(Self.seconds)
            guard let transcript = c.store.transcript(of: rec), !transcript.lines.isEmpty else {
                throw CLIError(exit: .notFound, message: String(localized: .recordingTranscriptNone(rec.file)))
            }
            let (lines, next) = transcript.window(from: start, to: end)
            let clock = { (t: TimeInterval) in AppLink.clock(Int(t)) }
            let session = rec.sessionId.flatMap { id in c.file.sessions.first { $0.id == id } }.map {
                c.file.reference(of: $0, calendar: r.ctx.calendar)
            }
            let shown = Shown(
                recording: rec.file, session: session, duration: clock(rec.duration),
                lines: lines.map { Line(at: clock($0.start), text: $0.text) }, next: next.map(clock))
            if g.json { return try printJSON(shown) }

            let span = "\(clock(start ?? 0))–\(clock(end ?? rec.duration))"
            say(String(localized: .recordingTranscriptHeader(rec.file, shown.duration, span)).styled(.bold))
            if lines.isEmpty { say(String(localized: .recordingTranscriptEmpty).styled(.dim)) }
            for l in shown.lines { say("[\(l.at)]".styled(.dim) + " " + l.text) }
            if let next = shown.next {
                let ref = "\(c.code)/\((rec.file as NSString).lastPathComponent)"
                let line =
                    "folio recording transcript \(MaterialCommand.Read.quoted(ref)) --from \(next)" + (to.map { " --to \($0)" } ?? "")
                say(String(localized: .readingNext(line)).styled(.dim))
            }
        }

        /// `750`, `12:30`, `1:02:03`, read as a recording's address reads its `#t=`.
        static func seconds(_ written: String) throws -> TimeInterval {
            let link = AppLink(string: "folio://recording/\(UUID().uuidString)#t=\(written.trimmingCharacters(in: .whitespaces))")
            guard case .time(let s)? = link?.anchor else {
                throw CLIError(exit: .usage, message: String(localized: .recordingTranscriptBadTime(written)))
            }
            return TimeInterval(s)
        }
    }
}

extension NoteCommand {
    struct Images: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteImagesAbstract),
            discussion: String(localized: .noteImagesDiscussion(ReadingLimit.imageEdge, ReadingLimit.images)))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteImagesHelpNote), valueName: "note"), completion: Complete.notes) var note:
            String = ""
        @Option(help: ArgumentHelp(String(localized: .noteImagesHelpFile), valueName: "file")) var file: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteImagesHelpFrom(ReadingLimit.images)), valueName: "n")) var from: Int?
        @Option(help: ArgumentHelp(String(localized: .picturesHelpOut), valueName: "folder"), completion: .directory) var out: String?

        struct Item: Encodable {
            var index: Int
            /// As the note wrote it, or as `--file` gave it.
            var written: String
            /// Course-relative; nil when the note names a file the course doesn't have.
            var path: String?
            var image: String?
        }

        struct Shown: Encodable {
            var note: String?
            var pictures: [Item]
            /// The `--from` to pass to go on.
            var next: Int?
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c: CourseRef
            let found: (note: NoteFile, path: String)?
            if note.contains("/") {
                let (course, n, path) = try r.notePath(note)
                c = course
                found = (n, path)
            } else {
                c = try r.course(note)
                found = nil
            }

            let store = c.store
            let listed: [NoteImageFile]
            if !file.isEmpty {
                listed = try file.map { try Self.locate($0, in: store, near: found?.note) }
            } else if let found {
                listed = store.noteImageFiles(of: found.note, body: try store.read(found.note))
            } else {
                // A course alone: what Notes/assets holds, named, for picking with `--file`.
                let assets = store.noteAssets().compactMap(store.coursePath(of:)).filter { MaterialFormat(path: $0) == .image }.sorted()
                return try show(Shown(note: nil, pictures: assets.enumerated().map { Item(index: $0 + 1, written: $1, path: $1) }), c)
            }

            let start = max(from ?? 1, 1)
            let window = Array(listed.enumerated().dropFirst(start - 1).prefix(ReadingLimit.images))
            let pictures = window.compactMap { i, f -> Pictures.Picture? in
                guard let path = f.path, let jpeg = store.pictureJPEG(path) else { return nil }
                let name = (path as NSString).lastPathComponent
                return Pictures.Picture(label: path, file: "\(i + 1) \((name as NSString).deletingPathExtension).jpg", data: jpeg)
            }
            let placed = try Pictures.hand(pictures, out: out, gist: r.ctx.gist.url)
            let placedAt = Dictionary(zip(pictures.map(\.label), placed), uniquingKeysWith: { a, _ in a })
            let last = start - 1 + window.count
            try show(
                Shown(
                    note: found?.path,
                    pictures: window.map { i, f in
                        Item(index: i + 1, written: f.written, path: f.path, image: f.path.flatMap { placedAt[$0] ?? nil })
                    },
                    next: last < listed.count ? last + 1 : nil), c)
        }

        func show(_ shown: Shown, _ c: CourseRef) throws {
            if g.json { return try printJSON(shown) }
            if shown.pictures.isEmpty { return say(String(localized: .noteImagesNone).styled(.dim)) }
            for p in shown.pictures {
                say(
                    "\(p.index). ".styled(.dim) + (p.path ?? p.written)
                        + (p.path == nil ? "  " + String(localized: .noteImagesMissing).styled(.yellow) : ""))
                if let image = p.image { say("   → \(image)".styled(.dim)) }
            }
            if let next = shown.next, let note = shown.note {
                say(
                    String(localized: .readingNext("folio note images \(MaterialCommand.Read.quoted("\(c.code)/\(note)")) --from \(next)"))
                        .styled(.dim))
            }
        }

        /// Beside the note first, then where a bare name in a note is looked for, then from the course folder.
        static func locate(_ written: String, in store: CourseStore, near note: NoteFile?) throws -> NoteImageFile {
            guard MaterialFormat(path: written) == .image else {
                throw CLIError(exit: .usage, message: String(localized: .noteImagesNotImage(written)))
            }
            let notes = CourseFolder.notes.rawValue
            let candidates =
                (note.flatMap { store.coursePath(of: $0.url.deletingLastPathComponent().appending(path: written)) }.map { [$0] } ?? [])
                + ["\(notes)/\(StandardLayout.noteAssetsFolder)/\(written)", "\(notes)/\(written)", written]
            guard
                let path = candidates.first(where: { store.contains($0) && FileManager.default.fileExists(atPath: store.fileURL($0).path) })
            else {
                throw CLIError(exit: .notFound, message: String(localized: .noteImagesNotFound(written)))
            }
            return NoteImageFile(written: written, path: path)
        }
    }
}
