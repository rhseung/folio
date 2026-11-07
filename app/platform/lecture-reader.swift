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

/// Reads a lecture PDF for its sections: the outline first, then each page's title, and only then Claude, which
/// gets the titles and the course's units. Matching to units by name happens here too, so every caller proposes the
/// same thing. Nothing is written: the result is a proposal the add sheet or the split screen shows.
enum LectureReader {
    struct Read: Sendable {
        var pageCount: Int
        var outline: [LectureReading.Bookmark]
        /// Empty when the outline already split the file: the pages aren't read then.
        var pages: [LectureReading.Page]
    }

    /// `progress` gets pages read and the page count, on the main actor.
    static func find(_ url: URL, units: [FolioDomain.Unit], claude: ClaudeClient?,
                     progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> LectureFinding {
        let report: @Sendable (Int, Int) -> Void = { done, total in Task { @MainActor in progress(done, total) } }
        guard let read = await Task.detached(operation: { read(url, progress: report) }).value else { return .unreadable }
        if let found = LectureReading.sections(outline: read.outline, pageCount: read.pageCount), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .outline)
        }
        if let found = LectureReading.sections(pages: read.pages, units: units.map(\.title)), let split = LectureSplit(found, pageCount: read.pageCount) {
            return .found(SectionMatch.match(split, units: units), .titles)
        }
        // Claude reads titles: a deck of pictures with no text gives it nothing either.
        if let claude, read.pages.contains(where: { $0.title != nil }),
           let split = try? await claude.lectureSections(file: url.lastPathComponent, pageTitles: read.pages.map(\.title), units: units) {
            return .found(split, .claude)
        }
        return .nothing(pageCount: read.pageCount)
    }

    /// Opens the file inside its security scope: the add sheet's files come from outside the sandbox.
    nonisolated static func read(_ url: URL, progress: @Sendable (Int, Int) -> Void) -> Read? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { return nil }
        var outline: [LectureReading.Bookmark] = []
        if let root = pdf.outlineRoot { walk(root, depth: -1, in: pdf, into: &outline) }
        let count = pdf.pageCount
        if LectureReading.sections(outline: outline, pageCount: count) != nil { return Read(pageCount: count, outline: outline, pages: []) }
        var pages: [LectureReading.Page] = []
        for i in 0..<count {
            pages.append(pdf.page(at: i).map(page) ?? LectureReading.Page(title: nil, words: 0))
            progress(i + 1, count)
        }
        return Read(pageCount: count, outline: outline, pages: pages)
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
    nonisolated static func page(_ page: PDFPage) -> LectureReading.Page {
        let text = page.attributedString ?? NSAttributedString()
        let string = text.string as NSString
        let words = text.string.split(whereSeparator: \.isWhitespace).count
        var best: (size: CGFloat, title: String)?
        var lines = 0
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byLines) { line, range, _, stop in
            guard let line = line?.trimmingCharacters(in: .whitespaces), !line.isEmpty else { return }
            var size: CGFloat = 0
            text.enumerateAttribute(.font, in: range) { font, _, _ in
                if let font = font as? PlatformFont { size = max(size, font.pointSize) }
            }
            if size > (best?.size ?? 0) { best = (size, line) }
            lines += 1
            if lines >= 4 { stop.pointee = true }
        }
        // `Page.words` counts what the slide has besides its title: a long title on a divider is still a divider.
        let titleWords = best?.title.split(whereSeparator: \.isWhitespace).count ?? 0
        return LectureReading.Page(title: best.map(\.title), words: max(words - titleWords, 0))
    }
}
