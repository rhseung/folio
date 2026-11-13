import FolioDomain
import SwiftUI
import WebKit

/// Shows rendered HTML in the Claude panel. The page's own JavaScript is off: answers are content, not code. Math is
/// typeset by the bundled reader script, which runs in the app's separate script world. Notes use `NotePreview`.
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

    func head(accent: CourseAccent) -> String {
        "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: accent))\(NoteStyle.css)</style></head>"
            + "<body class=\"note\" data-math=\"\(mathSyntax)\">"
    }

    func page(accent: CourseAccent) -> String {
        head(accent: accent) + "\(body)</body></html>"
    }

    @MainActor func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(
            WKUserScript(
                source: NoteStyle.reader, injectionTime: .atDocumentEnd,
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

    @MainActor func update(_ view: WKWebView, _ coordinator: Coordinator, accent: CourseAccent, openLink: OpenLinkAction) {
        coordinator.openNote = openNote
        coordinator.onAction = onAction
        coordinator.openLink = openLink
        let page = page(accent: accent)
        guard coordinator.loaded != page else { return }
        // Reloading would blank the page and lose its scroll on every keystroke.
        if coordinator.ready, let loaded = coordinator.loaded, loaded.hasPrefix(head(accent: accent)) {
            coordinator.loaded = page
            view.callAsyncJavaScript("window.folioReader?.update(html)", arguments: ["html": body], in: nil, in: .defaultClient)
            return
        }
        coordinator.loaded = page
        coordinator.ready = false
        coordinator.files.root = LocalFileScheme.root(for: baseURL)
        view.loadHTMLString(page, baseURL: LocalFileScheme.base(for: baseURL))
    }

    /// Keeps clicks out of the web view: app and note links open in the app, the rest in the app they belong to.
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var openNote: (String) -> Void = { _ in }
        var onAction: (URL) -> Void = { _ in }
        var openLink = OpenLinkAction()
        var loaded: String?
        var ready = false
        let files = LocalFileScheme()

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            open(url)
            return .cancel
        }

        /// The panel's own buttons here; every other link as a note's link opens, so an answer's `folio://exam/…`,
        /// `[[note:<ID>]]`, `obsidian:` and `mailto:` go where they would from the note itself.
        func open(_ url: URL) {
            if AppLink.isAction(url) { return onAction(url) }
            if url.scheme == LocalFileScheme.scheme {
                if url.pathExtension == "md" { openNote(url.deletingPathExtension().lastPathComponent) }
                return
            }
            NoteLinks.open(url.absoluteString, base: nil, openNote: openNote, openLink: openLink)
        }
    }
}

#if os(macOS)
extension HTMLView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {
        update(view, context.coordinator, accent: context.environment.accent, openLink: context.environment.openLink)
    }
}
#else
extension HTMLView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {
        update(view, context.coordinator, accent: context.environment.accent, openLink: context.environment.openLink)
    }
}
#endif
