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

// PDF의 다크 모드를 색 행렬 하나로 만든다. 색마다 색상은 그대로 두고 밝기만 뒤집으며(빨강은 빨강으로 남는다), 흰 종이와 검은 글자는 순수한 검정과 흰색 대신 테마의 다크 카드와 잉크 색이 된다. 뒤집기는
// 모든 채널에 `v + (1 - 2 luma(v))`이다. luma만으로 만들었으므로 색을 회색 축 방향으로만 옮겨 채도를 지킨다. 또 자기 자신의 역함수라서, `source(of:)`가 원하는 출력을 내는 입력을
// 이것으로 구한다. layer 필터는 선형 광도에서 돌므로 행렬을 tone curve로 감싸 sRGB 값에서 동작하게 한다. 토큰의 hex 값이 sRGB이고, sRGB에서는 뒤집은 중간 회색이 여전히 중간 회색으로
// 보인다.
struct DarkPaper {
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

    func source(of hex: UInt32) -> NSColor {
        let v = Self.flip((Self.rgb(hex) - paper) / (ink - paper))
        return NSColor(srgbRed: v.x, green: v.y, blue: v.z, alpha: 1)
    }

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
        return [
            CIFilter(name: "CILinearToSRGBToneCurve")!, matrix, CIFilter(name: "CIColorClamp")!, CIFilter(name: "CISRGBToneCurveToLinear")!,
        ]
    }
}
#endif

final class SteadyPDFView: PDFView {
    private var held: PDFDestination?
    private var letGo: DispatchWorkItem?
    // UIKit은 PDFView가 `document`에 필요한 것을 만들기 전에 `init(frame:)` 안에서 frame을 정한다. 그때 `document`를 읽으면 iPad에서 모든 PDF가 비정상적으로
    // 종료되었다.
    private var made = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        made = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        made = true
    }

    // 연달아 일어나는 폭 변경(구분선을 프레임마다 끄는 경우)의 처음에 한 번 잡고, 폭이 잠시 그대로 있은 뒤에야 놓는다. 프레임마다 다시 잡으면 PDFKit이 이미 스크롤 오프셋 기준으로 줄인 쪽에서 자리를
    // 읽어 오차가 쌓였고, 구분선을 끌면 6쪽이 9쪽으로 갔다. 아무리 작은 변경도 센다. 칸이 제자리로 미끄러지는 동안 폭이 1초 동안 1pt보다 작게 바뀌는데, 이것도 쌓였다.
    private func hold(newWidth: CGFloat) {
        guard made, document != nil, newWidth > 0, newWidth != bounds.width else { return }
        if held == nil {
            guard bounds.width > 0, let spot = currentDestination, spot.page != nil else { return }
            held = spot
        }
        letGo?.cancel()
        // PDFKit은 배치 단계가 끝난 뒤에 쪽을 새 폭에 맞춰 줄일 수 있으므로, 그 뒤에 놓는다.
        let work = DispatchWorkItem { [weak self] in self?.release() }
        letGo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settling, execute: work)
    }

    static let settling: TimeInterval = 0.2

    private func release(keep: Bool = false) {
        guard let spot = held else { return }
        if !keep { forget() }
        super.go(to: spot)
    }

    private func forget() {
        held = nil
        letGo?.cancel()
        letGo = nil
    }

    override func go(to page: PDFPage) {
        forget()
        super.go(to: page)
        waitForWidth(PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: displayBox).maxY)))
    }

    override func go(to destination: PDFDestination) {
        forget()
        super.go(to: destination)
        waitForWidth(destination)
    }

    private func waitForWidth(_ spot: PDFDestination) {
        if bounds.width == 0 { held = spot }
    }

    override func go(to selection: PDFSelection) {
        forget()
        super.go(to: selection)
    }

    #if os(macOS)
    override func setFrameSize(_ newSize: NSSize) {
        hold(newWidth: newSize.width)
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        release(keep: true)
    }
    #else
    override var frame: CGRect {
        get { super.frame }
        set {
            hold(newWidth: newValue.width)
            super.frame = newValue
        }
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            hold(newWidth: newValue.width)
            super.bounds = newValue
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        release(keep: true)
    }
    #endif
}

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
