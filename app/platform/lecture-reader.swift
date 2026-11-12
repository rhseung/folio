import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

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
    /// Claude was asked and gave no split: the line saying why. The user splits by hand or asks again.
    case failed(String, pageCount: Int)
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

/// Reads a lecture PDF for its sections. With Claude set up, Claude alone reads them: it gets each page's title, the
/// start of its text and, for a page with little text, its picture (#450). The outline and the slide titles are only
/// for a Mac without Claude, as they guess where a deck's own words would tell Claude better (2026-11-12 사용자).
/// Matching to units by name happens here too, so every caller proposes the same thing. Nothing is written: the
/// result is a proposal the add sheet or the split screen shows.
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
        let everyPage = claude != nil
        guard let read = await Task.detached(operation: { read(url, everyPage: everyPage, progress: report) }).value else { return .unreadable }
        if let claude {
            // A failed or empty answer is not passed on to the titles: their guess would then look like Claude's.
            let finding = await ask(claude, read: read, url: url, units: units)
            if case .found(let split) = finding { return .found(split, .claude) }
            return .failed(finding.message ?? "", pageCount: read.pageCount)
        }
        if let found = LectureReading.sections(outline: read.outline, pageCount: read.pageCount), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .outline)
        }
        if let found = LectureReading.sections(pages: read.pages, units: units.map(\.title)), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .titles)
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

    /// Opens the file inside its security scope: the add sheet's files come from outside the sandbox, and
    /// `PDFPages.open` reads through the file coordinator, which needs the scope too. `everyPage` reads the pages
    /// even when the outline splits the file, for Claude.
    nonisolated static func read(_ url: URL, everyPage: Bool, progress: @Sendable (Int, Int) -> Void) -> Read? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFPages.open(url) else { return nil }
        let outline = PDFPages.outline(pdf)
        let count = pdf.pageCount
        if !everyPage, LectureReading.sections(outline: outline, pageCount: count) != nil {
            return Read(pageCount: count, outline: outline, pages: [], texts: [])
        }
        var pages: [LectureReading.Page] = [], texts: [String] = []
        for i in 0..<count {
            // The whole text, figures and all: `LecturePage.pictured` counts them, and the cleaned text has none.
            let raw = pdf.page(at: i)?.attributedString ?? NSAttributedString()
            let text = PDFPages.text(of: raw, number: i + 1)
            pages.append(LectureReading.Page(title: text.title, words: text.words))
            texts.append(raw.string)
            progress(i + 1, count)
        }
        return Read(pageCount: count, outline: outline, pages: pages, texts: texts)
    }

    /// Small JPEGs of the given 0-based pages, keyed by page.
    nonisolated static func pictures(_ url: URL, pages: [Int]) -> [Int: Data] {
        guard !pages.isEmpty else { return [:] }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFPages.open(url) else { return [:] }
        var out: [Int: Data] = [:]
        for i in pages {
            if let page = pdf.page(at: i), let data = PDFPages.jpeg(page, edge: Int(LecturePage.thumbnail)) { out[i] = data }
        }
        return out
    }
}
