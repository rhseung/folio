import FolioDomain
import SwiftUI

#if os(macOS)
// TeX 오류는 화면에서 줄바꿈된 행이 아니라 파일의 줄을 세므로, 파일의 줄마다 번호를 붙인다.
final class LineNumberGutter: NSRulerView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // macOS 14부터 뷰가 기본으로 잘라 내지 않는다. viewport는 보이는 줄 위의 줄도 배치하므로, 잘라 내지 않으면 그 번호가 페이지 막대 위에 놓인다.
        clipsToBounds = true
        let center = NotificationCenter.default
        // ruler는 텍스트가 바뀌거나 크기를 바꾼 뒤 배치가 끝나도 저절로 다시 그려지지 않는다.
        for name in [NSText.didChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(
                center.addObserver(forName: name, object: textView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
        }
        refresh()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private var font: NSFont { NoteLook.font(NoteLook.smallSize, mono: true) }

    private func refresh() {
        let lines = (textView?.string ?? "").reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let digits = String(max(lines, 99)).count
        let width = ceil(("0" as NSString).size(withAttributes: [.font: font]).width * CGFloat(digits)) + Theme.Space.l * 2
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager,
            let viewport = layout.textViewportLayoutController.viewportRange
        else { return }
        let string = textView.string as NSString
        let first = content.offset(from: content.documentRange.location, to: viewport.location)
        var line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: min(first, string.length)), options: [.byLines, .substringNotRequired])
        { _, _, _, _ in line += 1 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NoteLook.text3]
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        layout.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY <= visible.maxY else { return false }
            defer { line += 1 }
            guard frame.maxY >= visible.minY else { return true }
            let row = fragment.textLineFragments.first
            let rowHeight = row?.typographicBounds.height ?? frame.height
            let label = String(line) as NSString
            let size = label.size(withAttributes: attributes)
            let top = convert(NSPoint(x: 0, y: frame.minY + origin.y), from: textView).y
            label.draw(
                at: NSPoint(x: ruleThickness - Theme.Space.s - size.width, y: top + (rowHeight - size.height) / 2),
                withAttributes: attributes)
            return true
        }
    }
}
#endif
