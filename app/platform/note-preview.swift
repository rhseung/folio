import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

/// The note preview: the note rendered by `HTMLRenderer`, as the Claude panel renders answers, in a web view. It's read
/// only; task boxes tick and callouts fold, and everything else is changed in the edit view.
struct NotePreview {
    var text: String
    var baseURL: URL?
    var math: MathSyntax = .latex
    var openNote: (String) -> Void = { _ in }
    /// Writes a ticked box back: its line in `text`, what the line should still hold, and its new text. False when the
    /// line no longer holds it. Without it boxes don't tick.
    var edit: (@MainActor (_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool)?
    /// Set beside the editor: the preview follows the editor's scroll.
    var link: PreviewLink?
    /// What ⌘E does while the preview has the keyboard. The web view would otherwise take the key for itself.
    var toggleMode: (@MainActor () -> Void)?

    @MainActor final class Coordinator {
        let page = NotePreviewPage.take()
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor func update(_ page: NotePreviewPage, accent: CourseAccent, dark: Bool) {
        page.openNote = openNote
        page.edit = edit
        page.toggleMode = toggleMode
        if link?.page !== page { link?.page = page }
        page.link = link
        page.show(text, baseURL: baseURL, math: math, accent: accent, dark: dark)
    }
}

#if os(macOS)
extension NotePreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewWebView {
        update(context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return context.coordinator.page.view
    }

    func updateNSView(_ view: PreviewWebView, context: Context) {
        update(context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
    }

    static func dismantleNSView(_ view: PreviewWebView, coordinator: Coordinator) { coordinator.page.recycle() }
}
#else
extension NotePreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewWebView {
        update(context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return context.coordinator.page.view
    }

    func updateUIView(_ view: PreviewWebView, context: Context) {
        update(context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
    }

    static func dismantleUIView(_ view: PreviewWebView, coordinator: Coordinator) { coordinator.page.recycle() }
}
#endif

/// Carries the editor's scroll to the preview beside it. Not observed state: going through SwiftUI would render the
/// note again on every step of a scroll.
@MainActor final class PreviewLink {
    weak var page: NotePreviewPage?
    private(set) var last: (line: Int, frac: Double)?

    func follow(line: Int, frac: Double) {
        last = (line, frac)
        refollow()
    }

    func refollow() {
        guard let last else { return }
        page?.follow(line: last.line, frac: last.frac)
    }
}

/// The preview's web view and what it shows. Pages are kept and handed out again (`take`, `recycle`): a new web view
/// starts a web process and parses the bundled scripts, which made opening a note slow.
@MainActor final class NotePreviewPage: NSObject, WKNavigationDelegate {
    let view: PreviewWebView
    private let files = LocalFileScheme()
    let widgets: NoteWidgets

    var openNote: (String) -> Void = { _ in }
    var edit: (@MainActor (Int, Int, String, String) -> Bool)?
    var toggleMode: (@MainActor () -> Void)? {
        didSet { view.toggleMode = toggleMode }
    }
    weak var link: PreviewLink?

    /// The page holds the stylesheet and scripts but no note until `show`: `ready` once it has loaded.
    private(set) var ready = false
    /// What the page was last asked to show, and whether it has finished showing it.
    private var shown: Shown?
    private var wanted: Shown?
    private(set) var rendering = false
    /// Lines of `text` above the body, which block lines and ticks are counted from.
    private var offset = 0
    private var lines: [Substring] = []
    /// Set by a tick here, so the note coming back with it doesn't scroll the page to the editor.
    private var ticked = false
    /// A scroll to follow the editor, held while the last one runs: the editor sends one per frame.
    private var following: (line: Int, frac: Double)?
    private var followRunning = false

    private struct Shown: Equatable {
        var text: String
        var baseURL: URL?
        var math: MathSyntax
        var accent: CourseAccent
        var editable: Bool
    }

    // MARK: Pool

    private static var idle: [NotePreviewPage] = []
    /// One page kept ready beyond those open, so the next note opens without waiting for a web process.
    private static let spare = 1

    static func take() -> NotePreviewPage {
        let page = idle.popLast() ?? NotePreviewPage()
        if idle.count < spare {
            // After this update, so the note being opened isn't held up by the spare.
            Task { @MainActor in if idle.count < spare { idle.append(NotePreviewPage()) } }
        }
        return page
    }

    func recycle() {
        openNote = { _ in }
        edit = nil
        toggleMode = nil
        link = nil
        wanted = nil
        following = nil
        widgets.reset()
        files.root = nil
        if ready, shown != nil {
            shown = nil
            view.callAsyncJavaScript("window.folioPreview?.reset()", arguments: [:], in: nil, in: .defaultClient)
        }
        // Kept only up to two idle pages: a split screen of notes closing at once shouldn't keep every web process.
        if Self.idle.count < Self.spare + 1, !Self.idle.contains(self) { Self.idle.append(self) }
    }

    // MARK: Making

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Widgets run their own code in frames; the note itself has none, and the page's policy forbids any.
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        widgets = NoteWidgets(scripts: scripts)
        config.setURLSchemeHandler(files, forURLScheme: LocalFileScheme.scheme)
        config.setURLSchemeHandler(widgets.files, forURLScheme: WidgetFiles.scheme)
        view = PreviewWebView(frame: .zero, configuration: config)
        super.init()
        view.page = self
        scripts.add(Messages(self), contentWorld: .defaultClient, name: Messages.name)
        widgets.resized = { [weak self] key, height in
            self?.view.callAsyncJavaScript("window.folioPreview?.size(key, height)", arguments: ["key": key, "height": height], in: nil, in: .defaultClient)
        }
        view.navigationDelegate = self
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        #endif
        load()
    }

    static let shellURL = URL(string: "\(LocalFileScheme.scheme)://local/")!

    /// Images resolve against `base`, which `show` points at the note's folder. The page may run no script of its own
    /// and load nothing but the note's files and its widgets.
    private static func shell(theme: String) -> String {
        let policy = [
            "default-src 'none'", "script-src 'none'", "style-src 'unsafe-inline'", "font-src data:",
            "img-src \(LocalFileScheme.scheme): data: blob:", "media-src \(LocalFileScheme.scheme):", "frame-src \(WidgetFiles.scheme):",
        ].joined(separator: "; ")
        return "<!doctype html><html><head><meta charset=utf-8><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
            + "<base href=\"\(shellURL.absoluteString)\"><style id=\"folio-theme\">\(theme)</style><style>\(NoteStyle.css)</style></head>"
            + "<body class=\"note preview\"></body></html>"
    }

    private func load() {
        ready = false
        shown = nil
        view.loadHTMLString(Self.shell(theme: NoteStyle.variables(accent: wanted?.accent ?? .gray)), baseURL: Self.shellURL)
    }

    // MARK: Showing

    func show(_ text: String, baseURL: URL?, math: MathSyntax, accent: CourseAccent, dark: Bool) {
        #if os(macOS)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if view.appearance?.name != appearance?.name { view.appearance = appearance }
        #else
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        #endif
        wanted = Shown(text: text, baseURL: baseURL, math: math, accent: accent, editable: edit != nil)
        render()
    }

    private func render() {
        guard ready, !rendering, let wanted, wanted != shown else { return }
        let note = ParsedNote(wanted.text)
        lines = wanted.text.split(separator: "\n", omittingEmptySubsequences: false)
        offset = max(0, lines.count - note.body.split(separator: "\n", omittingEmptySubsequences: false).count)
        files.root = LocalFileScheme.root(for: wanted.baseURL)
        widgets.begin(folder: wanted.baseURL, accent: wanted.accent)
        let blocks: [[String: Any]] = HTMLRenderer.blocks(note).map { block in
            var out: [String: Any] = ["html": widgets.frame(for: block.html) ?? block.html, "line": NSNull()]
            if let lines = block.lines { out["line"] = lines.lowerBound + offset }
            return out
        }
        widgets.end()
        let options: [String: Any] = [
            "math": wanted.math.rawValue, "editable": wanted.editable,
            "base": LocalFileScheme.base(for: wanted.baseURL)?.absoluteString ?? Self.shellURL.absoluteString,
        ]
        let theme = NoteStyle.variables(accent: wanted.accent)
        let accentChanged = shown?.accent != wanted.accent
        shown = wanted
        rendering = true
        Task {
            if accentChanged { _ = try? await view.callAsyncJavaScript("window.folioPreview?.theme(css)", arguments: ["css": theme], contentWorld: .defaultClient) }
            _ = try? await view.callAsyncJavaScript("window.folioPreview?.show(blocks, options)", arguments: ["blocks": blocks, "options": options], contentWorld: .defaultClient)
            rendering = false
            // Beside the editor the page follows it, except right after a tick here, which leaves the editor still.
            if ticked { ticked = false } else { link?.refollow() }
            render()
        }
    }

    /// The page has the note it was last given, with every widget's height known: what tests wait for.
    var settled: Bool { ready && !rendering && wanted == shown && !followRunning && widgets.settled }

    // MARK: Following the editor

    func follow(line: Int, frac: Double) {
        following = (line, frac)
        guard ready, !followRunning, !rendering else { return }
        runFollow()
    }

    private func runFollow() {
        guard let next = following else { return }
        following = nil
        followRunning = true
        Task {
            _ = try? await view.callAsyncJavaScript("window.folioPreview?.follow(line, frac)", arguments: ["line": next.line, "frac": next.frac],
                                                     contentWorld: .defaultClient)
            followRunning = false
            runFollow()
        }
    }

    // MARK: Messages from the page

    /// Holds the page weakly: the content controller keeps its handlers, and the page keeps the controller.
    private final class Messages: NSObject, WKScriptMessageHandler {
        static let name = "folioPreview"
        weak var page: NotePreviewPage?
        init(_ page: NotePreviewPage) { self.page = page }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], message.frameInfo.isMainFrame else { return }
            // Boxes carry their line in the note's body, below any frontmatter.
            if body["type"] as? String == "task", let line = body["line"] as? Int, let page { page.tick(line: page.offset + line) }
        }
    }

    /// Ticks or clears the box on line `line` of the note's text, through `edit`.
    @discardableResult func tick(line: Int) -> Bool {
        guard let edit, line >= 1, line <= lines.count else { return false }
        let old = String(lines[line - 1])
        guard let new = TaskBox.toggled(old), edit(line, line, old, new) else { return false }
        ticked = link != nil
        return true
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        render()
        if following != nil { runFollow() }
    }

    /// A crashed web process leaves a blank view; the page is loaded and shown again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let frame = action.targetFrame else { return .cancel }
        // A widget's frame stays on its page or blank: anywhere else, its address could carry data out.
        guard frame.isMainFrame else { return WidgetFiles.allows(url) ? .allow : .cancel }
        if action.navigationType == .linkActivated {
            // Only the note's own links: a widget may not send the note anywhere.
            if (action.sourceFrame as WKFrameInfo?)?.isMainFrame ?? true { await open(url) }
            return .cancel
        }
        return url == Self.shellURL || url.absoluteString == "about:blank" ? .allow : .cancel
    }

    private func open(_ url: URL) async {
        if url.scheme == LocalFileScheme.scheme, let fragment = url.fragment, url.pathExtension != "md" {
            // A link to a block or heading on this page.
            _ = try? await view.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView()", arguments: ["id": fragment.removingPercentEncoding ?? fragment],
                                                     contentWorld: .defaultClient)
            return
        }
        if url.scheme == LocalFileScheme.scheme {
            if url.pathExtension == "md" { openNote(url.deletingPathExtension().lastPathComponent) }
            return
        }
        NoteLinks.open(url.absoluteString, base: nil, openNote: openNote)
    }
}

#if os(macOS)
final class PreviewWebView: WKWebView {
    var toggleMode: (@MainActor () -> Void)?
    /// For tests, which find the view in SwiftUI's and reach the page through it.
    weak var page: NotePreviewPage?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "e", let toggleMode {
            toggleMode()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The page is the app's, not a site: going back or reloading would leave it blank, and links open only by a click.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let dropped: Set<String> = [
            "WKMenuItemIdentifierReload", "WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward",
            "WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierOpenImageInNewWindow",
            "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierOpenFrameInNewWindow", "WKMenuItemIdentifierInspectElement",
        ]
        for item in menu.items where dropped.contains(item.identifier?.rawValue ?? "") { menu.removeItem(item) }
        super.willOpenMenu(menu, with: event)
    }
}
#else
final class PreviewWebView: WKWebView {
    var toggleMode: (@MainActor () -> Void)?
    /// For tests, which find the view in SwiftUI's and reach the page through it.
    weak var page: NotePreviewPage?
}
#endif
