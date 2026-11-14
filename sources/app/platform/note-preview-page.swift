import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

// 페이지는 남겨 두었다가 다시 쓴다(`take`, `recycle`). 새 웹 뷰는 웹 프로세스를 띄우고 번들 스크립트를 다시 파싱하므로 노트를 여는 일이 느렸다.
@MainActor final class NotePreviewPage: NSObject, WKNavigationDelegate {
    let view: PreviewWebView
    private let files = LocalFileScheme()
    let widgets: NoteWidgets

    var openNote: (String) -> Void = { _ in }
    var openLink = OpenLinkAction()
    var noteLink: AppLink?
    var embeds: NoteEmbedSource?
    fileprivate(set) var menuHref: String?
    fileprivate(set) var menuAnchor: AppLink.Anchor?
    fileprivate(set) var selectionAnchor: AppLink.Anchor?
    private var revealed: AppLink.Anchor?
    private var revealing: AppLink.Anchor?
    var edit: (@MainActor (Int, Int, String, String) -> Bool)?
    var toggleMode: (@MainActor () -> Void)? {
        didSet { view.toggleMode = toggleMode }
    }
    weak var link: PreviewLink?
    weak var views: NoteViews?

    private(set) var ready = false
    private var shown: Shown?
    private var wanted: Shown?
    private(set) var rendering = false
    private var offset = 0
    private var lines: [Substring] = []
    private var ticked = false
    private var following: (line: Int, frac: Double)?
    private var followRunning = false

    private struct Shown: Equatable {
        var text: String
        var baseURL: URL?
        var math: MathSyntax
        var accent: CourseAccent
        var editable: Bool
        var revision: Int
    }

    // MARK: Pool

    private static var idle: [NotePreviewPage] = []
    private static let spare = 1

    static func take() -> NotePreviewPage {
        let page = idle.popLast() ?? NotePreviewPage()
        if idle.count < spare {
            Task { @MainActor in if idle.count < spare { idle.append(NotePreviewPage()) } }
        }
        return page
    }

    func recycle() {
        openNote = { _ in }
        openLink = OpenLinkAction()
        menuHref = nil
        menuAnchor = nil
        selectionAnchor = nil
        noteLink = nil
        embeds = nil
        revealed = nil
        revealing = nil
        edit = nil
        toggleMode = nil
        link = nil
        views = nil
        wanted = nil
        following = nil
        widgets.reset()
        files.root = nil
        if ready, shown != nil {
            shown = nil
            view.callAsyncJavaScript("window.folioPreview?.reset()", arguments: [:], in: nil, in: .defaultClient)
        }
        if Self.idle.count < Self.spare + 1, !Self.idle.contains(self) { Self.idle.append(self) }
    }

    // MARK: Making

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let scripts = config.userContentController
        scripts.addUserScript(
            WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        widgets = NoteWidgets(scripts: scripts)
        config.setURLSchemeHandler(files, forURLScheme: LocalFileScheme.scheme)
        config.setURLSchemeHandler(widgets.files, forURLScheme: WidgetFiles.scheme)
        view = PreviewWebView(frame: .zero, configuration: config)
        super.init()
        view.page = self
        scripts.add(Messages(self), contentWorld: .defaultClient, name: Messages.name)
        widgets.resized = { [weak self] key, height in
            self?.view.callAsyncJavaScript(
                "window.folioPreview?.size(key, height)", arguments: ["key": key, "height": height], in: nil, in: .defaultClient)
        }
        view.navigationDelegate = self
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.uiDelegate = self
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        #endif
        load()
    }

    static let shellURL = URL(string: "\(LocalFileScheme.scheme)://local/")!

    private static func shell(theme: String) -> String {
        let policy = [
            "default-src 'none'", "script-src 'none'", "style-src 'unsafe-inline'", "font-src data:",
            "img-src \(LocalFileScheme.scheme): data: blob:", "media-src \(LocalFileScheme.scheme):", "frame-src \(WidgetFiles.scheme):",
        ].joined(separator: "; ")
        return "<!doctype html><html><head><meta charset=utf-8><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
            + "<base href=\"\(shellURL.absoluteString)\"><style id=\"folio-theme\">\(theme)</style><style>\(NoteStyle.css)</style></head>"
            + "<body class=\"note preview\"\(figureLabels)></body></html>"
    }

    private static var figureLabels: String {
        let labels: [(String, LocalizedStringResource)] = [
            ("close", .notesFigureClose), ("previous", .notesFigurePrevious), ("next", .notesFigureNext),
            ("zoom-in", .notesFigureZoomIn), ("zoom-out", .notesFigureZoomOut), ("fit", .notesFigureFit),
        ]
        return labels.map { name, label in
            let text = String(localized: label).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            return " data-label-\(name)=\"\(text)\""
        }.joined()
    }

    private func load() {
        ready = false
        shown = nil
        view.loadHTMLString(Self.shell(theme: NoteStyle.variables(accent: wanted?.accent ?? .gray)), baseURL: Self.shellURL)
    }

    // MARK: Showing

    func show(_ text: String, baseURL: URL?, math: MathSyntax, accent: CourseAccent, dark: Bool, revision: Int = 0) {
        #if os(macOS)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if view.appearance?.name != appearance?.name { view.appearance = appearance }
        #else
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if view.overrideUserInterfaceStyle != style { view.overrideUserInterfaceStyle = style }
        #endif
        wanted = Shown(text: text, baseURL: baseURL, math: math, accent: accent, editable: edit != nil, revision: revision)
        render()
    }

    private func render() {
        guard ready, !rendering, let wanted, wanted != shown else { return }
        let note = ParsedNote(wanted.text)
        lines = wanted.text.split(separator: "\n", omittingEmptySubsequences: false)
        offset = max(0, lines.count - note.body.split(separator: "\n", omittingEmptySubsequences: false).count)
        files.root = LocalFileScheme.root(for: wanted.baseURL)
        widgets.begin(folder: wanted.baseURL, accent: wanted.accent)
        let embeds = embeds?.embeds(revision: wanted.revision, text: wanted.text)
        let blocks: [[String: Any]] = HTMLRenderer.blocks(note, embeds: embeds).map { block in
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
            if accentChanged {
                _ = try? await view.callAsyncJavaScript(
                    "window.folioPreview?.theme(css)", arguments: ["css": theme], contentWorld: .defaultClient)
            }
            _ = try? await view.callAsyncJavaScript(
                "window.folioPreview?.show(blocks, options)", arguments: ["blocks": blocks, "options": options],
                contentWorld: .defaultClient)
            rendering = false
            if ticked { ticked = false } else { link?.refollow() }
            runReveal()
            render()
        }
    }

    var settled: Bool { ready && !rendering && wanted == shown && !followRunning && widgets.settled }

    // MARK: Showing a heading or block

    func reveal(_ anchor: AppLink.Anchor?) {
        guard anchor != revealed else { return }
        revealed = anchor
        revealing = anchor
        if ready, !rendering, wanted == shown { runReveal() }
    }

    private func runReveal() {
        guard let anchor = revealing else { return }
        revealing = nil
        let id: String
        switch anchor {
        case .heading(let text): id = HTMLRenderer.slug(text)
        case .block(let block): id = "^" + block
        case .page, .time: return
        }
        Task {
            _ = try? await view.callAsyncJavaScript(
                "document.getElementById(id)?.scrollIntoView({block: 'start'})", arguments: ["id": id],
                contentWorld: .defaultClient)
        }
    }

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
            _ = try? await view.callAsyncJavaScript(
                "window.folioPreview?.follow(line, frac)", arguments: ["line": next.line, "frac": next.frac],
                contentWorld: .defaultClient)
            followRunning = false
            runFollow()
        }
    }

    func jump(line: Int) {
        Task {
            _ = try? await view.callAsyncJavaScript(
                "window.folioPreview?.jump(line)", arguments: ["line": line],
                contentWorld: .defaultClient)
        }
    }

    // MARK: Messages from the page

    // 페이지를 약하게 참조한다. content controller가 처리기를 참조하고 페이지가 controller를 참조하므로, 강하게 참조하면 순환이 생긴다.
    private final class Messages: NSObject, WKScriptMessageHandler {
        static let name = "folioPreview"
        weak var page: NotePreviewPage?
        init(_ page: NotePreviewPage) { self.page = page }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], message.frameInfo.isMainFrame else { return }
            if body["type"] as? String == "task", let line = body["line"] as? Int, let page { page.tick(line: page.offset + line) }
            let anchor = (body["block"] as? String).map(AppLink.Anchor.block) ?? (body["heading"] as? String).map(AppLink.Anchor.heading)
            if body["type"] as? String == "menu" {
                page?.menuHref = body["href"] as? String
                page?.menuAnchor = anchor
            }
            if body["type"] as? String == "selection" { page?.selectionAnchor = anchor }
            if body["type"] as? String == "top", let line = body["line"] as? Int { page?.views?.previewScrolled(line) }
        }
    }

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

    // 웹 프로세스가 비정상적으로 종료되면 뷰가 빈 화면으로 남으므로, 페이지를 다시 불러와 보인다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let frame = action.targetFrame else { return .cancel }
        // 위젯의 frame은 자기 페이지나 빈 페이지에만 머문다. 다른 주소로 가면 그 주소에 데이터를 실어 내보낼 수 있다.
        guard frame.isMainFrame else { return WidgetFiles.allows(url) ? .allow : .cancel }
        if action.navigationType == .linkActivated {
            if (action.sourceFrame as WKFrameInfo?)?.isMainFrame ?? true { await open(url) }
            return .cancel
        }
        return url == Self.shellURL || url.absoluteString == "about:blank" ? .allow : .cancel
    }

    func open(_ href: String, in placement: LinkPlacement) {
        NoteLinks.open(href, base: nil, in: placement, openNote: openNote, openLink: openLink)
    }

    private func open(_ url: URL) async {
        if url.scheme == LocalFileScheme.scheme, let fragment = url.fragment, url.pathExtension != "md" {
            _ = try? await view.callAsyncJavaScript(
                "document.getElementById(id)?.scrollIntoView()", arguments: ["id": fragment.removingPercentEncoding ?? fragment],
                contentWorld: .defaultClient)
            return
        }
        if url.scheme == LocalFileScheme.scheme {
            if url.pathExtension == "md" { openNote(url.deletingPathExtension().lastPathComponent) }
            return
        }
        NoteLinks.open(url.absoluteString, base: nil, openNote: openNote, openLink: openLink)
    }
}
