#if os(macOS)
import AppKit
import FolioMarkdown
import SwiftUI
import WebKit

/// The card a block reference (`[[노트#^블록]]`) shows in the edit view while the pointer rests on it, as the preview's
/// card (#284) does: the block drawn by the preview's renderer and stylesheet in a small page, so math and pictures look
/// the same in both. It floats over the text on glass and takes no clicks; it's a glance, like the math bubble, and the
/// preview's card is the one whose links are clicked.
@MainActor final class ReferenceCardPage: NSObject, WKNavigationDelegate {
    let host: ReferenceCardHost
    private let files = LocalFileScheme()
    private var loading: WKNavigation?
    private var loaded: ((CGFloat) -> Void)?
    private var tallest = CGFloat.greatestFiniteMagnitude

    var web: WKWebView { host.web }
    var shown: Bool { !host.isHidden }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd,
                                                                forMainFrameOnly: true, in: .defaultClient))
        config.setURLSchemeHandler(files, forURLScheme: LocalFileScheme.scheme)
        host = ReferenceCardHost(web: WKWebView(frame: .zero, configuration: config))
        super.init()
        web.navigationDelegate = self
        host.isHidden = true
    }

    /// Lays the card out `width` wide, off screen, and calls `done` with its height once its math is typeset. A block
    /// taller than `maxHeight` fades out at the bottom.
    func load(_ card: HTMLRenderer.ReferenceCard, math: String, accent: CourseAccent, baseURL: URL?, width: CGFloat, maxHeight: CGFloat,
              done: @escaping (CGFloat) -> Void) {
        hide()
        loaded = done
        tallest = maxHeight
        // Barely high while it loads, so the page's height is its content's, not the view's.
        host.resize(CGSize(width: width, height: Theme.Space.xxs))
        files.root = LocalFileScheme.root(for: baseURL)
        let page = "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: accent))\(NoteStyle.css)\(Self.css)</style></head>"
            + "<body class=\"note\" data-math=\"\(card.math ?? math)\">\(card.html)</body></html>"
        loading = web.loadHTMLString(page, baseURL: LocalFileScheme.base(for: baseURL))
    }

    func hide() {
        loading = nil
        loaded = nil
        host.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === loading, let done = loaded else { return }
        loading = nil
        loaded = nil
        let tallest = tallest
        Task {
            // The card takes no scroll, unlike the preview's, so a cut block says there is more by fading out.
            let measure = "const h = Math.ceil(document.body.getBoundingClientRect().height); "
                + "document.documentElement.classList.toggle('cut', h > tallest); return h"
            let height = try? await web.callAsyncJavaScript(measure, arguments: ["tallest": Double(tallest)], contentWorld: .defaultClient)
            guard let height = (height as? NSNumber)?.doubleValue, height > 0 else { return }
            done(CGFloat(height))
        }
    }

    // The note page's own padding is for a column; the card has the preview card's (`.ref-popover` in note.css).
    private static let css = "html{overflow:hidden}body.note{margin:0;padding:\(Int(Theme.Space.m))px \(Int(Theme.Space.l))px;max-width:none}"
        + "body.note>:first-child{margin-top:0}body.note>:last-child{margin-bottom:0}"
        + "html.cut{-webkit-mask-image:linear-gradient(to bottom,#000 calc(100% - \(Int(Theme.Space.xl))px),transparent)}"
}

/// The card over the editor: glass behind the page, as the completion menu floats (`floatingGlass()`).
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

    // It covers the lines under the link; a click there is meant for them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ReferenceCardGlass: View {
    var body: some View {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).floatingGlass()
    }
}
#endif
