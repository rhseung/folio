import CoreGraphics
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 같은 파일의 두 번째 `PDFDocument`로 main thread 밖에서 그린다. 화면의 문서는 `PDFView`와 main actor의 것이고, PDFKit은 한 문서를 두 thread에서 동시에 읽어도
// 된다고 보장하지 않는다.
@MainActor
final class PageThumbnails {
    // Retina 화면에서도 선명하도록, 행이 보이는 가장 큰 상자(렉처의 `Theme.Size.pageThumbnail`, 152x84)의 두 배 이상으로 둔다. 그 상자를 키우면 이 값도 키운다. 이 값의
    // 절반을 넘으면 쪽이 흐리게 나온다.
    nonisolated static let pixels = CGSize(width: 320, height: 176)
    private static let kept = 160

    private let renderer: PageRenderer
    private var images: [Int: CGImage] = [:]
    private var pending: [Int: Task<RenderedPage?, Never>] = [:]

    init(url: URL?) {
        renderer = PageRenderer(url: url)
    }

    func image(_ page: Int) async -> CGImage? {
        if let image = images[page] { return image }
        let task = pending[page] ?? Task { [renderer] in await renderer.render(page) }
        pending[page] = task
        let image = await task.value?.image
        pending[page] = nil
        if let image { keep(image, for: page) }
        return image
    }

    private func keep(_ image: CGImage, for page: Int) {
        images[page] = image
        guard images.count > Self.kept else { return }
        for far in images.keys.sorted(by: { abs($0 - page) > abs($1 - page) }).prefix(images.count - Self.kept) { images[far] = nil }
    }
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
