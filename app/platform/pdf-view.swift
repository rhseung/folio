import Observation
import PDFKit
import SwiftUI

/// Owns one PDFKit view so SwiftUI buttons (zoom, find, page) can drive it; SwiftUI has no PDF view of its own.
@MainActor @Observable
final class PDFController {
    @ObservationIgnored let view = PDFView()
    /// 0-based, follows scrolling.
    private(set) var page = 0
    let pageCount: Int
    private(set) var matches: [PDFSelection] = []
    private(set) var matchIndex = 0
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(document: PDFDocument, page: Int) {
        pageCount = document.pageCount
        view.document = document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        self.page = min(max(page, 0), max(pageCount - 1, 0))
        observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.view.currentPage, let doc = self.view.document else { return }
                self.page = doc.index(for: current)
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func go(to index: Int) {
        if let target = view.document?.page(at: index) { view.go(to: target) }
    }

    /// Jumps to the remembered page once the view has a size; before layout PDFKit ignores `go(to:)`.
    func restore() {
        let target = page
        DispatchQueue.main.async { [self] in go(to: target) }
    }

    func zoomIn() { view.zoomIn(nil) }
    func zoomOut() { view.zoomOut(nil) }
    func fit() { view.autoScales = true }

    /// Finds every occurrence and highlights them all; synchronous, so it runs on submit, not per keystroke.
    func find(_ text: String) {
        matches = text.isEmpty ? [] : view.document?.findString(text, withOptions: [.caseInsensitive, .diacriticInsensitive]) ?? []
        view.highlightedSelections = matches
        matchIndex = 0
        showMatch()
    }

    func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        showMatch()
    }

    private func showMatch() {
        guard matches.indices.contains(matchIndex) else { return }
        view.setCurrentSelection(matches[matchIndex], animate: true)
        view.go(to: matches[matchIndex])
    }
}

struct PDFKitView {
    let controller: PDFController
}

/// Page thumbnails for the controller's document; clicking one moves the main view.
struct PDFThumbnails {
    let controller: PDFController

    @MainActor func make() -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView()
        thumbnails.pdfView = controller.view
        thumbnails.thumbnailSize = CGSize(width: 96, height: 128)
        thumbnails.backgroundColor = .clear
        #if os(iOS)
        thumbnails.layoutMode = .vertical
        #endif
        return thumbnails
    }
}

#if os(macOS)
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        controller.restore()
        return controller.view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}

extension PDFThumbnails: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFThumbnailView { make() }
    func updateNSView(_ view: PDFThumbnailView, context: Context) {}
}
#else
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        controller.restore()
        return controller.view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

extension PDFThumbnails: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFThumbnailView { make() }
    func updateUIView(_ view: PDFThumbnailView, context: Context) {}
}
#endif
