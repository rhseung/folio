import FolioDomain
import FolioStorage
import WebKit

/// A `cb-widget` block: its HTML runs in a web view of its own over the attachment.
final class WidgetAttachment: NSTextAttachment, ViewAttachment {
    let view: PlatformView
    let inset: CGFloat = 0
    let below: CGFloat = 0

    init(view: WidgetWebView, size: CGSize) {
        self.view = view
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: .zero, size: size)
        #if os(macOS)
        image = NSImage(size: size, flipped: false) { _ in true }
        #else
        image = UIImage()
        #endif
    }

    required init?(coder: NSCoder) { nil }
}

/// Keeps each widget's web view across renderings: the note is rendered anew on every edit, and a new view would
/// restart the widget and lose what was done in it.
@MainActor final class ReaderWidgets {
    private var views: [String: WidgetWebView] = [:]
    private var used: Set<String> = []

    func begin() { used = [] }

    func view(_ id: UUID, file: URL?, accent: CourseAccent) -> WidgetWebView {
        // The same widget may be placed twice in a note, and each place runs on its own.
        var n = 0
        while used.contains("\(id)#\(n)") { n += 1 }
        let key = "\(id)#\(n)"
        used.insert(key)
        if let view = views[key], view.file == file {
            view.accent = accent
            return view
        }
        let view = WidgetWebView(file: file, accent: accent)
        views[key] = view
        return view
    }

    func end() { views = views.filter { used.contains($0.key) } }
}

/// A widget's page, cut off from everything but its own file: no network, nothing kept between runs, no going to
/// another page. Widgets are written by Claude or pasted in, so they're treated as untrusted code.
final class WidgetWebView: WKWebView, AttachedView, WKNavigationDelegate {
    let file: URL?
    private let files: WidgetScheme
    var accent: CourseAccent {
        didSet {
            guard accent != oldValue else { return }
            installScripts()
            evaluateJavaScript("document.getElementById('folio-theme').textContent = \(Self.quoted(Self.themeCSS(accent)))")
        }
    }

    init(file: URL?, accent: CourseAccent) {
        self.file = file
        self.accent = accent
        files = WidgetScheme(file: file)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.setURLSchemeHandler(files, forURLScheme: WidgetScheme.scheme)
        super.init(frame: .zero, configuration: config)
        installScripts()
        navigationDelegate = self
        #if os(macOS)
        setValue(false, forKey: "drawsBackground")
        #else
        isOpaque = false
        backgroundColor = .clear
        scrollView.backgroundColor = .clear
        #endif
        load(URLRequest(url: WidgetScheme.page))
    }

    required init?(coder: NSCoder) { nil }

    private func installScripts() {
        let scripts = configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(source: Self.noPeers, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let theme = "const s = document.createElement('style'); s.id = 'folio-theme'; s.textContent = \(Self.quoted(Self.themeCSS(accent)));"
            + " document.documentElement.prepend(s);"
        scripts.addUserScript(WKUserScript(source: theme, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// The note's colors under the names note pages use (`var(--accent)`), and a page that starts out like the note:
    /// `:where` keeps these below anything the widget sets itself.
    static func themeCSS(_ accent: CourseAccent) -> String {
        NoteStyle.variables(accent: accent)
            + ":root{color-scheme:light dark}"
            + ":where(body){margin:0;font:14px/1.5 -apple-system,system-ui,sans-serif;color:var(--text);background:transparent}"
    }

    /// The page's security policy doesn't cover peer connections, which could otherwise carry data out.
    private static let noPeers = "for (const k of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel']) { try { delete window[k]; window[k] = undefined } catch {} }"

    private static func quoted(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        // Frames inside the page fall under its policy, which loads nothing from outside.
        if action.targetFrame?.isMainFrame == false { return .allow }
        var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
        bare?.fragment = nil
        if bare?.url == WidgetScheme.page { return .allow }
        if action.navigationType == .linkActivated, url.scheme == "http" || url.scheme == "https" {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            await UIApplication.shared.open(url)
            #endif
        }
        return .cancel
    }
}

/// Serves a widget's one file as its page, with a policy that lets it run its own inline code and nothing else.
@MainActor final class WidgetScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-widget"
    static let page = URL(string: "\(scheme)://widget/index.html")!
    static let policy = [
        "default-src 'none'", "script-src 'unsafe-inline' 'unsafe-eval'", "style-src 'unsafe-inline'",
        "img-src data: blob:", "font-src data:", "media-src data: blob:", "form-action 'none'", "base-uri 'none'",
    ].joined(separator: "; ")

    let file: URL?

    init(file: URL?) { self.file = file }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard task.request.url == Self.page else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let data = file.flatMap { LocalFile.read($0) } ?? Self.missing(file)
        let headers = ["Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": Self.policy]
        task.didReceive(HTTPURLResponse(url: Self.page, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private static func missing(_ file: URL?) -> Data {
        let name = file?.lastPathComponent ?? ""
        let text = String(localized: .notesWidgetMissing(name))
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return Data("<!doctype html><p style=\"color:var(--text-3);font-size:12px;padding:12px\">\(text)</p>".utf8)
    }
}
