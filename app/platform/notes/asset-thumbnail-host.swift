import SwiftUI

// 썸네일을 그리는 웹 뷰를 서랍이 있는 창에 붙인다. 웹 뷰는 창 밖에서는 그리지 않는다.
#if os(macOS)
struct AssetThumbnailHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HostView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { AssetThumbnails.shared.host(in: self) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#else
struct AssetThumbnailHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { HostView() }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class HostView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { AssetThumbnails.shared.host(in: self) }
        }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}
#endif
