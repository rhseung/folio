#if os(macOS)
import AppKit
import FolioMarkdown
import SwiftUI
import WebKit

final class ReferenceCardHost: NSView {
    let web: WKWebView
    private let glass = NSHostingView(rootView: ReferenceCardGlass())

    init(web: WKWebView) {
        self.web = web
        super.init(frame: .zero)
        web.setValue(false, forKey: "drawsBackground")
        web.wantsLayer = true
        web.layer?.cornerRadius = Theme.Radius.floating
        web.layer?.masksToBounds = true
        addSubview(glass)
        addSubview(web)
    }

    required init?(coder: NSCoder) { fatalError() }

    func resize(_ size: CGSize) {
        setFrameSize(size)
        glass.frame = bounds
        web.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ReferenceCardGlass: View {
    var body: some View {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).floatingGlass()
    }
}
#endif
