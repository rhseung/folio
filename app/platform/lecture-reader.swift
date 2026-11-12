import FolioAI
import FolioDomain
import Foundation
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where a lecture's proposed sections came from, in the order they are tried (#321).
enum LectureSource: Equatable, Sendable {
    case outline, titles, claude
}

/// A lecture's proposed split, or why there is none.
enum LectureFinding: Equatable, Sendable {
    case found(LectureSplit, LectureSource)
    /// Read, but nothing said where the units begin: the user splits by hand from one section.
    case nothing(pageCount: Int)
    /// Not a PDF Folio can read.
    case unreadable
}

/// What "Claude로 나누기" came back with (#450).
enum ClaudeFinding: Equatable, Sendable {
    case found(LectureSplit)
    /// Claude answered, but with nothing that splits the file.
    case nothing
    case unreadable
    /// Why the request failed, in the user's words.
    case failed(String)

    /// The line a screen shows for anything but a split.
    var message: String? {
        switch self {
        case .found: nil
        case .nothing: String(localized: .lectureClaudeNothing)
        case .unreadable: String(localized: .lectureClaudeUnreadable)
        case .failed(let why): String(localized: .lectureClaudeFailed(why))
        }
    }
}

/// The two screens' way to Claude: whether it can be asked, and asking it. Tests give a stand-in.
struct LectureClaude {
    /// Why the button is off; nil once Claude is set up. Read each time, as settings can connect it meanwhile.
    var off: @MainActor () -> String?
    var ask: @MainActor (URL, [FolioDomain.Unit]) async -> ClaudeFinding

    @MainActor static func of(_ workspace: Workspace, course: LoadedCourse) -> LectureClaude {
        LectureClaude(off: { workspace.claudeReady ? nil : String(localized: .lectureClaudeOff) }, ask: { url, units in
            guard workspace.claudeReady else { return .failed(String(localized: .lectureClaudeOff)) }
            return await LectureReader.askClaude(url, units: units, claude: workspace.claude(for: course))
        })
    }
}

/// Reads a lecture PDF for its sections: the outline first, then each page's title, and only then Claude, which
/// gets each page's title, the start of its text and, for a page with little text, its picture (#450). Matching to
/// units by name happens here too, so every caller proposes the same thing. Nothing is written: the result is a
/// proposal the add sheet or the split screen shows.
enum LectureReader {
    struct Read: Sendable {
        var pageCount: Int
        var outline: [LectureReading.Bookmark]
        /// Empty when the outline already split the file and the pages weren't asked for: they aren't read then.
        var pages: [LectureReading.Page]
        /// Each page's whole text, in step with `pages`.
        var texts: [String]
    }

    /// `progress` gets pages read and the page count, on the main actor.
    static func find(_ url: URL, units: [FolioDomain.Unit], claude: ClaudeClient?,
                     progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> LectureFinding {
        let report: @Sendable (Int, Int) -> Void = { done, total in Task { @MainActor in progress(done, total) } }
        guard let read = await Task.detached(operation: { read(url, everyPage: false, progress: report) }).value else { return .unreadable }
        if let found = LectureReading.sections(outline: read.outline, pageCount: read.pageCount), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .outline)
        }
        if let found = LectureReading.sections(pages: read.pages, units: units.map(\.title)), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .titles)
        }
        if let claude, case .found(let split) = await ask(claude, read: read, url: url, units: units) {
            return .found(split, .claude)
        }
        return .nothing(pageCount: read.pageCount)
    }

    /// Straight to Claude, whatever the outline and titles would say: the user asked for its reading.
    static func askClaude(_ url: URL, units: [FolioDomain.Unit], claude: ClaudeClient) async -> ClaudeFinding {
        guard let read = await Task.detached(operation: { read(url, everyPage: true, progress: { _, _ in }) }).value else { return .unreadable }
        return await ask(claude, read: read, url: url, units: units)
    }

    private static func ask(_ claude: ClaudeClient, read: Read, url: URL, units: [FolioDomain.Unit]) async -> ClaudeFinding {
        let pictured = LecturePage.pictured(texts: read.texts, titles: read.pages.map(\.title))
        // A deck with no titles and nothing to picture gives Claude nothing to read.
        guard read.pages.contains(where: { $0.title != nil }) || !pictured.isEmpty else { return .nothing }
        let pictures = await Task.detached(operation: { Self.pictures(url, pages: pictured) }).value
        let pages = read.pages.indices.map { LecturePage(title: read.pages[$0].title, body: read.texts[$0], image: pictures[$0]) }
        do {
            return try await claude.lectureSections(file: url.lastPathComponent, pages: pages, units: units).map(ClaudeFinding.found) ?? .nothing
        } catch {
            return .failed(ClaudeModel.message(for: error))
        }
    }

    /// Opens the file inside its security scope: the add sheet's files come from outside the sandbox. `everyPage`
    /// reads the pages even when the outline splits the file, for Claude.
    nonisolated static func read(_ url: URL, everyPage: Bool, progress: @Sendable (Int, Int) -> Void) -> Read? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { return nil }
        var outline: [LectureReading.Bookmark] = []
        if let root = pdf.outlineRoot { walk(root, depth: -1, in: pdf, into: &outline) }
        let count = pdf.pageCount
        if !everyPage, LectureReading.sections(outline: outline, pageCount: count) != nil {
            return Read(pageCount: count, outline: outline, pages: [], texts: [])
        }
        var pages: [LectureReading.Page] = [], texts: [String] = []
        for i in 0..<count {
            let read = pdf.page(at: i).map(Self.read) ?? (page: LectureReading.Page(title: nil, words: 0), text: "")
            pages.append(read.page)
            texts.append(read.text)
            progress(i + 1, count)
        }
        return Read(pageCount: count, outline: outline, pages: pages, texts: texts)
    }

    /// Small JPEGs of the given 0-based pages, keyed by page.
    nonisolated static func pictures(_ url: URL, pages: [Int]) -> [Int: Data] {
        guard !pages.isEmpty else { return [:] }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else { return [:] }
        var out: [Int: Data] = [:]
        for i in pages {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox).size
            let turned = page.rotation % 180 != 0
            let (w, h) = turned ? (box.height, box.width) : (box.width, box.height)
            guard w > 0, h > 0 else { continue }
            let scale = LecturePage.thumbnail / max(w, h)
            let image = page.thumbnail(of: CGSize(width: (w * scale).rounded(), height: (h * scale).rounded()), for: .mediaBox)
            if let data = jpeg(image) { out[i] = data }
        }
        return out
    }

    private nonisolated static func jpeg(_ image: PlatformImage) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #else
        return image.jpegData(compressionQuality: 0.7)
        #endif
    }

    private nonisolated static func walk(_ item: PDFOutline, depth: Int, in pdf: PDFDocument, into out: inout [LectureReading.Bookmark]) {
        if depth >= 0, let label = item.label, let page = item.destination?.page {
            out.append(LectureReading.Bookmark(title: label, page: pdf.index(for: page) + 1, depth: depth))
        }
        for i in 0..<item.numberOfChildren {
            if let child = item.child(at: i) { walk(child, depth: depth + 1, in: pdf, into: &out) }
        }
    }

    /// A slide's title is the line set in the largest type among its first few lines. Reading the largest type on the
    /// whole page would take a big formula or a diagram's label instead.
    nonisolated static func page(_ page: PDFPage) -> LectureReading.Page { read(page).page }

    private nonisolated static let blank = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FFFC}"))

    private nonisolated static func read(_ page: PDFPage) -> (page: LectureReading.Page, text: String) {
        let text = page.attributedString ?? NSAttributedString()
        let string = text.string as NSString
        // Figures left out: a diagram's labels came with one stand-in character per drawing, each counted a word.
        let words = LecturePage.words(text.string)
        var best: (size: CGFloat, title: String)?
        var lines = 0
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byLines) { line, range, _, stop in
            // A line of figures only isn't a line of the slide: a diagram's stand-ins came first on a page and used
            // up the four lines before its title.
            guard let line = line?.trimmingCharacters(in: Self.blank), !line.isEmpty else { return }
            var size: CGFloat = 0
            text.enumerateAttribute(.font, in: range) { font, _, _ in
                if let font = font as? PlatformFont { size = max(size, font.pointSize) }
            }
            if size > (best?.size ?? 0) { best = (size, line) }
            lines += 1
            if lines >= 4 { stop.pointee = true }
        }
        // `Page.words` counts what the slide has besides its title: a long title on a divider is still a divider.
        let titleWords = best.map { LecturePage.words($0.title) } ?? 0
        return (LectureReading.Page(title: best.map(\.title), words: max(words - titleWords, 0)), text.string)
    }
}
