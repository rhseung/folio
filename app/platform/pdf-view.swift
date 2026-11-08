import CoreImage
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

    /// Also kept as the page, for a view not yet in the hierarchy: PDFKit ignores `go(to:)` before layout, and the
    /// `restore()` that follows would otherwise go back to the page it had.
    func go(to index: Int) {
        guard let target = view.document?.page(at: index) else { return }
        page = min(max(index, 0), max(pageCount - 1, 0))
        view.go(to: target)
    }

    /// Jumps to the remembered page once the view has a size; before layout PDFKit ignores `go(to:)`.
    func restore() {
        let target = page
        DispatchQueue.main.async { [self] in go(to: target) }
    }

    #if os(macOS)
    /// Shows the pages on the theme's dark paper without touching the file (`DarkPaper`). PDFKit draws the gaps
    /// between pages through the same filter, so their color goes in as what the filter turns into the dark line.
    /// Mac only: UIKit layers take no Core Image filters, so on iPad the pages keep their printed white.
    func darken(_ on: Bool) {
        guard on != !view.contentFilters.isEmpty else { return }
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        // An inverted drop shadow glows around each page.
        view.pageShadowsEnabled = !on
        view.contentFilters = on ? DarkPaper.theme.filters : []
        if on { lightBackground = view.backgroundColor }
        view.backgroundColor = on ? DarkPaper.theme.source(of: Swatch.lineSoft.dark) : lightBackground ?? view.backgroundColor
    }

    /// ⌘-click, the TeX editors' way back to the source. A plain click stays PDFKit's, for selecting text and following
    /// links. Mac only: only a Mac builds the PDF, so only a Mac has the data that says where a point came from.
    func onCommandClick(_ handler: @escaping @MainActor (_ page: Int, _ point: CGPoint) -> Void) {
        commandClick = CommandClick(view: view, handler: handler)
    }
    #endif

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

#if os(macOS)
/// Reports a ⌘-click as a page index and a point in PDF points from that page's top-left corner, where TeX measures.
///
/// Watched as a local event monitor rather than a gesture recognizer: recognizers on a PDFView never sent their action
/// for a ⌘-press, as PDFKit tracks the press itself. Taken on the press and not passed on, so PDFKit doesn't also treat
/// it as a ⌘-click that extends the selection; a press without ⌘, or outside this view, goes through untouched.
@MainActor
private final class CommandClick {
    private var monitor: Any?

    init(view: PDFView, handler: @escaping @MainActor (Int, CGPoint) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view] event in
            let taken = MainActor.assumeIsolated {
                guard let view, event.modifierFlags.contains(.command), let window = view.window, event.window === window,
                      let document = view.document,
                      // The press must land on the PDF itself, not on a popover or sheet over it.
                      window.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: view) == true else { return false }
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

/// Dark mode for a PDF, as one color matrix: each color's lightness flips while its hue stays (red stays red), and
/// white paper and black type land on the theme's dark card and ink instead of pure black and white.
///
/// The flip is `v + (1 - 2·luma(v))` on every channel. Built from luma alone, it moves a color along the gray axis,
/// keeping its chroma; it is also its own inverse, which `source(of:)` uses to find what input gives a wanted output.
/// Layer filters run in linear light, so the matrix is wrapped in tone curves and works on sRGB values, where the token
/// hex values are, and where a flipped mid gray still looks mid gray.
struct DarkPaper {
    // Rec. 601 luma, the weights a hue rotation keeps fixed.
    static let luma = SIMD3<Double>(0.299, 0.587, 0.114)
    static let theme = DarkPaper(paper: Swatch.card.dark, ink: Swatch.text.dark)

    let paper: SIMD3<Double>, ink: SIMD3<Double>

    init(paper: UInt32, ink: UInt32) {
        self.paper = Self.rgb(paper)
        self.ink = Self.rgb(ink)
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double(hex >> 16 & 0xFF), Double(hex >> 8 & 0xFF), Double(hex & 0xFF)) / 255
    }

    static func flip(_ v: SIMD3<Double>) -> SIMD3<Double> {
        v + SIMD3(repeating: 1 - 2 * (luma * v).sum())
    }

    func apply(_ v: SIMD3<Double>) -> SIMD3<Double> {
        paper + (ink - paper) * Self.flip(v)
    }

    /// The color that comes out as `hex` once filtered.
    func source(of hex: UInt32) -> NSColor {
        let v = Self.flip((Self.rgb(hex) - paper) / (ink - paper))
        return NSColor(srgbRed: v.x, green: v.y, blue: v.z, alpha: 1)
    }

    /// Row `i` of the matrix: (ink − paper)ᵢ times the flip's row, offset by inkᵢ (the flip of black is all ones).
    var filters: [CIFilter] {
        let scale = ink - paper
        func row(_ i: Int) -> CIVector {
            var weights = -2 * Self.luma
            weights[i] += 1
            weights *= scale[i]
            return CIVector(x: weights.x, y: weights.y, z: weights.z, w: 0)
        }
        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(row(0), forKey: "inputRVector")
        matrix.setValue(row(1), forKey: "inputGVector")
        matrix.setValue(row(2), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: ink.x, y: ink.y, z: ink.z, w: 0), forKey: "inputBiasVector")
        // A saturated color flips past white (pure red to 1.4, 0.4, 0.4 before the paper and ink range); clamped, it stays a
        // light red.
        return [CIFilter(name: "CILinearToSRGBToneCurve")!, matrix, CIFilter(name: "CIColorClamp")!, CIFilter(name: "CISRGBToneCurveToLinear")!]
    }
}
#endif

struct PDFKitView {
    let controller: PDFController
}

#if os(macOS)
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        controller.restore()
        PDFLinks.attach(to: controller.view, opener: context.environment.openLink)
        return controller.view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        controller.restore()
        PDFLinks.attach(to: controller.view, opener: context.environment.openLink)
        return controller.view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif
