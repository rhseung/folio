import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

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
            var text: String?
            var words: Int
            var figures: Int
            var image: String?
        }

        struct Shown: Encodable {
            var path: String
            var pageCount: Int
            var first: Int
            var last: Int
            var outline: [Bookmark]?
            var pages: [Page]
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
