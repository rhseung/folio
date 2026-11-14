import FolioDomain
import FolioMarkdown
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

public struct PDFPageText: Equatable, Sendable {
    public var page: Int
    public var title: String?
    public var text: String
    public var words: Int
    public var figures: Int

    public init(page: Int, title: String? = nil, text: String, words: Int, figures: Int) {
        self.page = page
        self.title = title
        self.text = text
        self.words = words
        self.figures = figures
    }
}

public enum PDFPages {
    public static func open(_ url: URL) -> PDFDocument? {
        guard let data = try? CoordinatedFile.read(url), let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { return nil }
        return pdf
    }

    public static func text(of page: PDFPage, number: Int) -> PDFPageText {
        text(of: page.attributedString ?? NSAttributedString(), number: number)
    }

    public static func text(of raw: NSAttributedString, number: Int) -> PDFPageText {
        let title = title(of: raw)
        let words = max(PageText.words(raw.string) - (title.map(PageText.words) ?? 0), 0)
        return PDFPageText(
            page: number, title: title, text: PageText.cleaned(raw.string), words: words, figures: PageText.figures(raw.string))
    }

    static func title(of text: NSAttributedString) -> String? {
        let string = text.string as NSString
        var lines: [(text: String, size: Double)] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byLines) { line, range, _, stop in
            guard let line, !line.trimmingCharacters(in: PageText.blank).isEmpty else { return }
            var size: CGFloat = 0
            text.enumerateAttribute(.font, in: range) { font, _, _ in
                if let font = font as? PlatformFont { size = max(size, font.pointSize) }
            }
            lines.append((line, Double(size)))
            if lines.count >= PageText.titleLines { stop.pointee = true }
        }
        return PageText.title(lines)
    }

    public static func outline(_ pdf: PDFDocument) -> [LectureReading.Bookmark] {
        var out: [LectureReading.Bookmark] = []
        func walk(_ item: PDFOutline, depth: Int) {
            if depth >= 0, let label = item.label, let page = item.destination?.page {
                out.append(LectureReading.Bookmark(title: label, page: pdf.index(for: page) + 1, depth: depth))
            }
            for i in 0..<item.numberOfChildren {
                if let child = item.child(at: i) { walk(child, depth: depth + 1) }
            }
        }
        if let root = pdf.outlineRoot { walk(root, depth: -1) }
        return out
    }

    public static func jpeg(_ page: PDFPage, edge: Int = ReadingLimit.imageEdge) -> Data? {
        let box = page.bounds(for: .mediaBox).size
        let turned = page.rotation % 180 != 0
        let (w, h) = turned ? (box.height, box.width) : (box.width, box.height)
        guard w > 0, h > 0 else { return nil }
        let scale = CGFloat(edge) / max(w, h)
        let image = page.thumbnail(of: CGSize(width: (w * scale).rounded(), height: (h * scale).rounded()), for: .mediaBox)
        #if os(macOS)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let cg = image.cgImage else { return nil }
        #endif
        return ClaudeJPEG.of(cg, edge: edge)
    }
}

enum ClaudeJPEG {
    static func of(_ image: CGImage, edge: Int) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            dest, image,
            [
                kCGImageDestinationLossyCompressionQuality: 0.8,
                kCGImageDestinationImageMaxPixelSize: edge,
            ] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

public struct NoteImageFile: Equatable, Sendable {
    public var written: String
    public var path: String?

    public init(written: String, path: String?) {
        self.written = written
        self.path = path
    }
}

extension CourseStore {
    public func noteImageFiles(of note: NoteFile, body: String) -> [NoteImageFile] {
        NoteImages.references(in: body).map { ref in
            let written =
                switch ref {
                case .path(let p): p
                case .name(let n): n
                }
            return NoteImageFile(written: written, path: imageURL(ref, of: note).flatMap(coursePath(of:)))
        }
    }

    func imageURL(_ ref: NoteImages.Reference, of note: NoteFile) -> URL? {
        let root = url.standardizedFileURL.path + "/"
        let candidates: [URL] =
            switch ref {
            case .path(let p): [note.url.deletingLastPathComponent().appending(path: p)]
            case .name(let n):
                [noteAssetsURL.appending(path: n), notesURL.appending(path: n), note.url.deletingLastPathComponent().appending(path: n)]
            }
        return candidates.map(\.standardizedFileURL).first { $0.path.hasPrefix(root) && FileManager.default.fileExists(atPath: $0.path) }
    }

    public func pictureJPEG(_ path: String, edge: Int = ReadingLimit.imageEdge) -> Data? {
        guard contains(path), let data = try? CoordinatedFile.read(fileURL(path)) else { return nil }
        return Self.contextJPEG(data, maxEdge: edge)
    }
}
