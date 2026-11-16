import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

enum LectureReader {
    struct Read: Sendable {
        var pageCount: Int
        var outline: [LectureReading.Bookmark]
        var pages: [LectureReading.Page]
        var texts: [String]
    }

    static func find(
        _ url: URL, units: [FolioDomain.Unit], claude: ClaudeClient?,
        progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async -> LectureFinding {
        let report: @Sendable (Int, Int) -> Void = { done, total in Task { @MainActor in progress(done, total) } }
        let everyPage = claude != nil
        guard let read = await Task.detached(operation: { read(url, everyPage: everyPage, progress: report) }).value else {
            return .unreadable
        }

        if let claude {
            let finding = await ask(claude, read: read, url: url, units: units)
            if case .found(let split) = finding { return .found(split, .claude) }
            return .failed(finding.message ?? "", pageCount: read.pageCount)
        }
        if let found = LectureReading.sections(outline: read.outline, pageCount: read.pageCount),
            let split = LectureSplit(found, pageCount: read.pageCount)
        {
            return .found(SectionMatch.match(split, units: units), .outline)
        }
        if let found = LectureReading.sections(pages: read.pages, units: units.map(\.title)),
            let split = LectureSplit(found, pageCount: read.pageCount)
        {
            return .found(SectionMatch.match(split, units: units), .titles)
        }
        return .nothing(pageCount: read.pageCount)
    }

    static func askClaude(_ url: URL, units: [FolioDomain.Unit], claude: ClaudeClient) async -> ClaudeFinding {
        guard let read = await Task.detached(operation: { read(url, everyPage: true, progress: { _, _ in }) }).value else {
            return .unreadable
        }
        return await ask(claude, read: read, url: url, units: units)
    }

    private static func ask(_ claude: ClaudeClient, read: Read, url: URL, units: [FolioDomain.Unit]) async -> ClaudeFinding {
        let pictured = LecturePage.pictured(texts: read.texts, titles: read.pages.map(\.title))
        guard read.pages.contains(where: { $0.title != nil }) || !pictured.isEmpty else { return .nothing }
        let pictures = await Task.detached(operation: { Self.pictures(url, pages: pictured) }).value
        let pages = read.pages.indices.map { LecturePage(title: read.pages[$0].title, body: read.texts[$0], image: pictures[$0]) }
        do {
            return try await claude.lectureSections(file: url.lastPathComponent, pages: pages, units: units).map(ClaudeFinding.found)
                ?? .nothing
        } catch {
            return .failed(ClaudeModel.message(for: error))
        }
    }

    // 파일을 security scope 안에서 연다. 추가 시트의 파일은 sandbox 밖에서 오고, `PDFPages.open`은 file coordinator로 읽는데 이것도 scope가 필요하다.
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
            // `LecturePage.pictured`가 그림을 세는데 정리한 텍스트에는 그림이 없으므로, 그림을 포함한 원래 텍스트를 읽는다.
            let raw = pdf.page(at: i)?.attributedString ?? NSAttributedString()
            let text = PDFPages.text(of: raw, number: i + 1)
            pages.append(LectureReading.Page(title: text.title, words: text.words))
            texts.append(raw.string)
            progress(i + 1, count)
        }
        return Read(pageCount: count, outline: outline, pages: pages, texts: texts)
    }

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
