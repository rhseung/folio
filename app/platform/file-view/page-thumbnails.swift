import CoreGraphics
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Small pictures of one PDF's pages, drawn as their rows come into view and kept while the file is open. The page
/// strip and the split screen both read them, so a page drawn for one is there for the other.
///
/// Drawn off the main thread from a second `PDFDocument` of the same file: the one on screen belongs to its `PDFView`
/// and the main actor, and PDFKit doesn't say one document may be read from two threads at once.
@MainActor
final class PageThumbnails {
    /// Pixels on the longer sides of the box a thumbnail is drawn into: twice the largest box a row shows (the split
    /// screen's), so it stays sharp on a Retina display.
    nonisolated static let pixels = CGSize(width: 320, height: 176)
    /// Pages kept at most. A row costs about 200KB; a textbook of 500 pages kept whole would hold 100MB.
    private static let kept = 160

    private let renderer: PageRenderer
    private var images: [Int: CGImage] = [:]
    private var pending: [Int: Task<RenderedPage?, Never>] = [:]

    init(url: URL?) {
        renderer = PageRenderer(url: url)
    }

    /// `page` is 1-based, as the strip counts.
    func image(_ page: Int) async -> CGImage? {
        if let image = images[page] { return image }
        // Asked twice while drawing (a row scrolled away and back), it is drawn once.
        let task = pending[page] ?? Task { [renderer] in await renderer.render(page) }
        pending[page] = task
        let image = await task.value?.image
        pending[page] = nil
        if let image { keep(image, for: page) }
        return image
    }

    /// Past the limit, the pages furthest from the one just drawn go first: those are the rows least likely to be
    /// scrolled back to.
    private func keep(_ image: CGImage, for page: Int) {
        images[page] = image
        guard images.count > Self.kept else { return }
        for far in images.keys.sorted(by: { abs($0 - page) > abs($1 - page) }).prefix(images.count - Self.kept) { images[far] = nil }
    }
}

/// A drawn page handed from the renderer to the main actor. CGImage is immutable once made, but the SDK doesn't mark
/// it `Sendable`.
struct RenderedPage: @unchecked Sendable {
    let image: CGImage
}

private actor PageRenderer {
    private let document: PDFDocument?

    init(url: URL?) {
        document = url.flatMap(PDFDocument.init(url:))
    }

    func render(_ page: Int) -> RenderedPage? {
        guard let pdfPage = document?.page(at: page - 1) else { return nil }
        let thumbnail = pdfPage.thumbnail(of: PageThumbnails.pixels, for: .mediaBox)
        #if os(macOS)
        let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        let image = thumbnail.cgImage
        #endif
        return image.map(RenderedPage.init)
    }
}
