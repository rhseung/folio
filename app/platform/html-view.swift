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
    /// Set for the preview beside the editor: the note is swapped in place as it changes, and the page follows the
    /// editor's scroll.
    var link: PreviewLink?
    /// Set to let the reader type into blocks: called with a block's lines in the body, the text they should still
    /// hold and their new text; false when they no longer hold it, and the page is shown anew.
    var edit: (@MainActor (_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool)?
    /// What ⌘E does while the page has the keyboard, if anything.
    var toggleMode: (@MainActor () -> Void)?

    func head(accent: CourseAccent) -> String {
        "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: accent))\(NoteStyle.css)</style></head>"
            + "<body class=\"note\" data-math=\"\(mathSyntax)\"\(edit == nil ? "" : " data-editable")>"
    }

    func page(accent: CourseAccent) -> String {
        head(accent: accent) + "\(body)</body></html>"
    }

    @MainActor func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd,
                                                                forMainFrameOnly: true, in: .defaultClient))
        config.userContentController.add(coordinator, contentWorld: .defaultClient, name: "folioReader")
        config.setURLSchemeHandler(coordinator.files, forURLScheme: LocalFileScheme.scheme)
        #if os(macOS)
        let view = NoteWebView(frame: .zero, configuration: config)
        #else
        let view = WKWebView(frame: .zero, configuration: config)
        #endif
        view.navigationDelegate = coordinator
        link?.view = view
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
        coordinator.link = link
        coordinator.edit = edit
        coordinator.body = body
        #if os(macOS)
        (view as? NoteWebView)?.shortcut = { [weak view, edit, toggleMode] key in
            switch key {
            case "e":
                toggleMode?()
                return toggleMode != nil
            case "b", "i" where edit != nil:
                view?.callAsyncJavaScript("window.folioReader?.format(command)", arguments: ["command": key == "b" ? "bold" : "italic"],
                                          in: nil, in: .defaultClient)
                return true
            default:
                return false
            }
        }
        #endif
        let page = page(accent: accent)
        guard coordinator.loaded != page else { return }
        // Reloading would blank the page and lose its scroll on every keystroke.
        if coordinator.ready, let loaded = coordinator.loaded, loaded.hasPrefix(head(accent: accent)) {
            coordinator.loaded = page
            view.callAsyncJavaScript("window.folioReader?.update(html)", arguments: ["html": body], in: nil, in: .defaultClient) { _ in
                coordinator.link?.refollow()
            }
            return
        }
        coordinator.loaded = page
        coordinator.ready = false
        coordinator.files.root = LocalFileScheme.root(for: baseURL)
        view.loadHTMLString(page, baseURL: LocalFileScheme.base(for: baseURL))
    }

    /// Keeps clicks out of the web view: note links open in the app, web links in the browser.
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var openNote: (String) -> Void = { _ in }
        var onAction: (URL) -> Void = { _ in }
        var edit: (@MainActor (Int, Int, String, String) -> Bool)?
        var body = ""
        var loaded: String?
        var ready = false
        var link: PreviewLink?
        let files = LocalFileScheme()

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            link?.refollow()
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let msg = message.body as? [String: Any] else { return }
            switch msg["type"] as? String {
            case "edit":
                guard let from = msg["from"] as? Int, let to = msg["to"] as? Int, let old = msg["old"] as? String,
                      let new = msg["text"] as? String, let edit else { return }
                if !edit(from, to, old, new) {
                    message.webView?.callAsyncJavaScript("window.folioReader?.update(html, true)", arguments: ["html": body], in: nil, in: .defaultClient)
                }
            case "open":
                if let href = msg["href"] as? String, let url = URL(string: href) { Task { await open(url) } }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            await open(url)
            return .cancel
        }

        func open(_ url: URL) async {
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
        }
    }
}

#if os(macOS)
/// Takes the note's ⌘ shortcuts before WebKit, which claims every ⌘ key for the page, so neither the page's script
/// nor SwiftUI's shortcuts would see them. Matched by key code, which doesn't change with the input source (Korean).
class NoteWebView: WKWebView {
    var shortcut: (@MainActor (Character) -> Bool)?
    static let letters: [UInt16: Character] = [11: "b", 34: "i", 14: "e"]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if (window?.firstResponder as? NSView)?.isDescendant(of: self) == true,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = Self.letters[event.keyCode], shortcut?(key) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

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

/// Carries the editor's scroll to the preview beside it. Not observed state: going through SwiftUI would render the
/// note again on every step of a scroll.
@MainActor final class PreviewLink {
    weak var view: WKWebView?
    private var last: (line: Int, frac: Double)?

    func follow(line: Int, frac: Double) {
        last = (line, frac)
        refollow()
    }

    func refollow() {
        guard let last else { return }
        view?.callAsyncJavaScript("window.folioReader?.follow(line, frac)", arguments: ["line": last.line, "frac": last.frac], in: nil, in: .defaultClient)
    }
}
