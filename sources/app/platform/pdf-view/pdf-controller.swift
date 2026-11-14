import CoreImage
import Observation
import PDFKit
import SwiftUI

@MainActor @Observable
final class PDFController {
    #if DEBUG
    @ObservationIgnored let view: PDFView = ProcessInfo.processInfo.environment["FOLIO_PLAIN_PDF"] != nil ? PDFView() : SteadyPDFView()
    #else
    @ObservationIgnored let view: PDFView = SteadyPDFView()
    #endif
    private(set) var page = 0
    let pageCount: Int
    private(set) var matches: [PDFSelection] = []
    private(set) var matchIndex = 0
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored lazy var thumbnails = PageThumbnails(url: view.document?.documentURL)
    #if os(macOS)
    @ObservationIgnored private var lightBackground: NSColor?
    @ObservationIgnored private var commandClick: CommandClick?
    #endif

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

    // 뷰가 아직 뷰 계층에 없을 때를 위해 쪽 번호로도 남긴다. PDFKit은 배치 전의 `go(to:)`를 무시하고, 그 뒤에 오는 `restore()`가 원래 쪽으로 되돌리기 때문이다.
    func go(to index: Int) {
        guard let target = view.document?.page(at: index) else { return }
        page = min(max(index, 0), max(pageCount - 1, 0))
        view.go(to: target)
    }

    func restore() {
        let target = page
        DispatchQueue.main.async { [self] in go(to: target) }
    }

    #if os(macOS)
    // 파일을 건드리지 않고 테마의 다크 종이 위에 쪽을 보인다(`DarkPaper`). PDFKit은 쪽 사이의 틈도 같은 필터로 그리므로, 틈의 색에는 필터를 거쳐 다크 구분선이 되는 색을 넣는다. Mac
    // 전용이다. UIKit layer는 Core Image 필터를 받지 않으므로 iPad에서는 쪽이 인쇄한 흰색 그대로 남는다.
    func darken(_ on: Bool) {
        guard on != !view.contentFilters.isEmpty else { return }
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        view.pageShadowsEnabled = !on
        view.contentFilters = on ? DarkPaper.theme.filters : []
        if on { lightBackground = view.backgroundColor }
        view.backgroundColor = on ? DarkPaper.theme.source(of: Swatch.lineSoft.dark) : lightBackground ?? view.backgroundColor
    }

    func onCommandClick(_ handler: @escaping @MainActor (_ page: Int, _ point: CGPoint) -> Void) {
        commandClick = CommandClick(view: view, handler: handler)
    }
    #endif

    func zoomIn() { view.zoomIn(nil) }
    func zoomOut() { view.zoomOut(nil) }
    func fit() { view.autoScales = true }

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

#if os(macOS)
// 쪽 번호와 그 쪽 왼쪽 위 기준의 PDF point로 알린다. TeX가 그 기준으로 잰다. gesture recognizer가 아니라 local event monitor로 받는다. PDFKit이 누르기를 직접
// 추적하므로, PDFView에 붙인 recognizer는 ⌘ 누르기에 action을 보내지 않았다. 누를 때 받아서 넘기지 않으므로 PDFKit이 이를 선택을 넓히는 ⌘ 클릭으로 처리하지 않는다. ⌘ 없는 누르기와
// 이 뷰 밖의 누르기는 그대로 지나간다.
@MainActor
private final class CommandClick {
    private var monitor: Any?

    init(view: PDFView, handler: @escaping @MainActor (Int, CGPoint) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view] event in
            let taken = MainActor.assumeIsolated {
                guard let view, event.modifierFlags.contains(.command), let window = view.window, event.window === window,
                    let document = view.document,
                    window.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: view) == true
                else { return false }
                let location = view.convert(event.locationInWindow, from: nil)
                guard let page = view.page(for: location, nearest: true) else { return false }
                let point = view.convert(location, to: page)
                let box = page.bounds(for: .mediaBox)
                handler(document.index(for: page), CGPoint(x: point.x - box.minX, y: box.maxY - point.y))
                return true
            }
            return taken ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
#endif
