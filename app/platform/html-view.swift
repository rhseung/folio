import SwiftUI
import WebKit

/// Shows rendered note HTML. The page's own JavaScript is off: notes are content, not code. Math is typeset by the
/// bundled reader script, which runs in the app's separate script world (widgets get their own sandbox later).
struct HTMLView {
    let body: String
    /// The note's folder, so `assets/…` images resolve.
    var baseURL: URL?
    /// How `$…$` in this note is written: `latex` or `asciimath`.
    var mathSyntax = "latex"
    /// Called with a note title when a `[[wikilink]]` or a link to a `.md` file is clicked.
    var openNote: (String) -> Void = { _ in }
    /// Called with `folio://action/…` links, which a page uses for buttons since JavaScript is off.
    var onAction: (URL) -> Void = { _ in }

    func page(accent: CourseAccent) -> String {
        "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: accent))\(NoteStyle.css)</style></head>"
            + "<body class=\"note\" data-math=\"\(mathSyntax)\">\(body)</body></html>"
    }

    @MainActor func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd,
                                                                forMainFrameOnly: true, in: .defaultClient))
        config.setURLSchemeHandler(coordinator.files, forURLScheme: LocalFileScheme.scheme)
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = coordinator
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        return view
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor func update(_ view: WKWebView, _ coordinator: Coordinator, accent: CourseAccent) {
        coordinator.openNote = openNote
        coordinator.onAction = onAction
        let page = page(accent: accent)
        guard coordinator.loaded != page else { return }
        coordinator.loaded = page
        coordinator.files.root = LocalFileScheme.root(for: baseURL)
        view.loadHTMLString(page, baseURL: LocalFileScheme.base(for: baseURL))
    }

    /// Keeps clicks out of the web view: note links open in the app, web links in the browser.
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var openNote: (String) -> Void = { _ in }
        var onAction: (URL) -> Void = { _ in }
        var loaded: String?
        let files = LocalFileScheme()

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            switch url.scheme {
            case "folio" where url.host == "note":
                openNote(String(url.path.dropFirst()))
            case "folio" where url.host == "action":
                onAction(url)
            case LocalFileScheme.scheme where url.pathExtension == "md":
                openNote(url.deletingPathExtension().lastPathComponent)
            case "http", "https":
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
            default:
                break
            }
            return .cancel
        }
    }
}

#if os(macOS)
extension HTMLView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, context.coordinator, accent: context.environment.accent) }
}
#else
extension HTMLView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, context.coordinator, accent: context.environment.accent) }
}
#endif
