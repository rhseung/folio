import SwiftUI

// 수식 그림을 그리는 보이지 않는 페이지는 화면에 보이는 창 안에서만 그린다. 편집 보기가 없는 화면(카드, 문제 풀이)은 이 뷰로 자기 창에 페이지를 붙인다.
#if os(macOS)
struct MathHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HostView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { NoteMath.shared.host(in: self) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#else
struct MathHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { HostView() }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class HostView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { NoteMath.shared.host(in: self) }
        }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}
#endif
