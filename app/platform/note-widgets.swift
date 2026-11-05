import FolioDomain
import FolioStorage
import WebKit

/// `cb-widget` blocks in the note preview: each runs its course's `.folio/widgets/<id>.html` in a frame of the note's
/// page. Widgets are written by Claude or pasted in, so they're treated as untrusted code: the frame is sandboxed to an
/// origin of its own (it can't reach the note's page or navigate it), its policy lets it run only its own inline code
/// and load nothing, nothing is kept between runs, and it can't go to another page.
@MainActor final class NoteWidgets {
    let files = WidgetFiles()
    /// Called with a frame's key and the height its page needs.
    var resized: (String, CGFloat) -> Void = { _, _ in }
    private var accent = CourseAccent.gray
    private var used: [UUID: Int] = [:]
    private var keys: Set<String> = []
    private var sizers: [String: WidgetSizer] = [:]
    /// The frame each widget last reported from, so tests can look inside it.
    private(set) var frames: [String: WKFrameInfo] = [:]

    init(scripts: WKUserContentController) {
        scripts.addUserScript(WKUserScript(source: Self.noPeers, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        scripts.addUserScript(WKUserScript(source: Self.themeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // In a world of its own, so the widget's code can neither see nor fake the reports.
        scripts.addUserScript(WKUserScript(source: Self.sizeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Self.world))
        scripts.add(Reports(self), contentWorld: Self.world, name: Reports.name)
    }

    func begin(folder: URL?, accent: CourseAccent) {
        files.folder = folder
        self.accent = accent
        used = [:]
        keys = []
    }

    func end() {
        sizers = sizers.filter { keys.contains($0.key) }
        frames = frames.filter { keys.contains($0.key) }
    }

    func reset() {
        begin(folder: nil, accent: .gray)
        end()
    }

    /// Every widget shown has said how tall its page is.
    var settled: Bool { keys.allSatisfy { sizers[$0]?.height != nil } }

    /// The frame for a top-level widget block, or nil for any other block. A widget in a table cell stays the inert
    /// placeholder `HTMLRenderer` makes: a cell is no place to run one.
    func frame(for html: String) -> String? {
        guard let m = html.wholeMatch(of: /<div class="cb-widget" data-widget="([0-9A-Fa-f-]{36})"(?: style="height:(-?\d+)px")?><\/div>\n?/),
              let id = UUID(uuidString: String(m.1)) else { return nil }
        // The same widget may be placed twice in a note, and each place runs on its own.
        let n = used[id, default: 0]
        used[id] = n + 1
        // A rewritten file makes a new frame, which starts the widget anew; an unchanged one keeps running.
        let file = files.folder.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) }
        let stamp = file.flatMap { LocalFile.modified($0) }.map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "none"
        let key = "\(id.uuidString)-\(n)-\(stamp)"
        keys.insert(key)
        // A block with no height would hide its frame, and a hidden page never says how tall it is. The height its
        // page said is kept by the preview's script, not written here: the frame's HTML has to stay the same for the
        // preview to keep it, and the widget running, when the note is shown again.
        let height = max(m.2.flatMap { Int($0) } ?? 320, 16)
        if sizers[key] == nil { sizers[key] = WidgetSizer() }
        var url = URLComponents()
        url.scheme = WidgetFiles.scheme
        url.host = "widget"
        url.path = "/" + id.uuidString
        // Every character but letters and digits escaped: `+`, `&` and `=` left as they are would split the theme apart,
        // and the address goes into an attribute as it is.
        let encode = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
        url.percentEncodedQueryItems = [URLQueryItem(name: "k", value: encode(key)), URLQueryItem(name: "t", value: encode(Self.themeCSS(accent)))]
        let src = url.url?.absoluteString ?? ""
        return "<iframe class=\"cb-widget\" sandbox=\"allow-scripts\" data-key=\"\(key)\" data-height=\"\(height)\" src=\"\(src)\"></iframe>\n"
    }

    fileprivate func report(_ key: String, page: Double, view: Double, frame: WKFrameInfo) {
        guard keys.contains(key) else { return }
        frames[key] = frame
        if let height = sizers[key]?.report(page: page, view: view) { resized(key, height) }
    }

    // MARK: Scripts

    private static let world = WKContentWorld.world(name: "folio-widget")

    /// Holds the widgets weakly: the content controller keeps its handlers, and the page keeps the controller.
    private final class Reports: NSObject, WKScriptMessageHandler {
        static let name = "size"
        weak var widgets: NoteWidgets?
        init(_ widgets: NoteWidgets) { self.widgets = widgets }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let key = body["k"] as? String, let page = body["h"] as? Double, let view = body["v"] as? Double
            else { return }
            widgets?.report(key, page: page, view: view, frame: message.frameInfo)
        }
    }

    /// The root element's own box, not `scrollHeight`, which is never less than the frame and so could only grow.
    private static let sizeScript = """
    if (location.protocol === '\(WidgetFiles.scheme):') {
      const html = document.documentElement, k = new URLSearchParams(location.search).get('k')
      const report = () => webkit.messageHandlers.\(Reports.name).postMessage({ k, h: html.getBoundingClientRect().height, v: innerHeight })
      new ResizeObserver(report).observe(html); addEventListener('resize', report); report()
    }
    """

    /// The note's colors under the names note pages use, before the widget's own styles. In a block: a top-level name
    /// here would clash with the same name declared by the widget's own script.
    private static let themeScript = """
    if (location.protocol === '\(WidgetFiles.scheme):') {
      const t = new URLSearchParams(location.search).get('t')
      if (t !== null) { const s = document.createElement('style'); s.id = 'folio-theme'; s.textContent = t; document.documentElement.prepend(s) }
    }
    """

    /// A page that starts out like the note: `:where` keeps these below anything the widget sets itself.
    static func themeCSS(_ accent: CourseAccent) -> String {
        NoteStyle.variables(accent: accent)
            + ":root{color-scheme:light dark}"
            + ":where(body){margin:0;font:14px/1.5 -apple-system,system-ui,sans-serif;color:var(--text);background:transparent}"
    }

    /// The page's security policy doesn't cover peer connections, which could otherwise carry data out.
    private static let noPeers = "for (const k of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel']) { try { delete window[k]; window[k] = undefined } catch {} }"
}

/// Follows what a widget's page says about its height. A page sized by its frame (`100vh`, `50vh`,
/// `calc(600px - 100vh)`) changes by the same share of every change of the frame, so following it would never settle;
/// it keeps the height it was first shown at. Content that grows again while the frame follows it (a font, an image, a
/// chart drawn a frame later) changes by amounts of its own, so one change of both isn't enough to tell.
struct WidgetSizer {
    private(set) var height: CGFloat?
    private var last: (page: Double, view: Double)?
    /// The frame's height at the first report, which is the height written in the block.
    private var start: Double?
    /// How much the page changed for each point the frame did, the last time both changed.
    private var share: Double?
    private var followsView = false

    /// The frame's new height, or nil when it stays.
    mutating func report(page: Double, view: Double) -> CGFloat? {
        // Before the frame is laid out it has no height, and a page sized by it would report none.
        guard view >= 1, !followsView else { return nil }
        defer { last = (page, view) }
        let start = start ?? view
        self.start = start
        if let last, abs(view - last.view) >= 0.5 {
            if abs(page - last.page) >= 0.5 {
                let share = (page - last.page) / (view - last.view)
                if let previous = self.share, abs(share - previous) < 0.01 {
                    followsView = true
                    return fit(start)
                }
                self.share = share
            } else {
                share = nil
            }
        }
        return fit(page)
    }

    private mutating func fit(_ page: Double) -> CGFloat? {
        let fitted = max(CGFloat(page).rounded(.up), 16)
        guard fitted != height else { return nil }
        height = fitted
        return fitted
    }
}

/// Serves each widget's one file as its frame's page, with a policy that lets it run its own inline code and nothing
/// else.
@MainActor final class WidgetFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-widget"
    static let policy = [
        "default-src 'none'", "script-src 'unsafe-inline' 'unsafe-eval'", "style-src 'unsafe-inline'",
        "img-src data: blob:", "font-src data:", "media-src data: blob:", "form-action 'none'", "base-uri 'none'",
    ].joined(separator: "; ")

    /// The note's folder, which names the course whose widgets are served.
    var folder: URL?

    /// A frame's policy loads nothing from outside, but a blank frame sent elsewhere would carry whatever is in its
    /// address out; so every frame stays on a widget's page or blank.
    static func allows(_ url: URL) -> Bool {
        url.scheme == "about" || (url.scheme == scheme && url.host == "widget")
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "widget", let id = UUID(uuidString: url.lastPathComponent) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let file = folder.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) }
        let data = file.flatMap { LocalFile.read($0) } ?? Self.notice(file)
        let headers = ["Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": Self.policy]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    static func notice(_ file: URL?) -> Data {
        let text = switch file {
        case nil: String(localized: .notesWidgetNoCourse)
        case let file? where LocalFile.exists(file): String(localized: .notesWidgetUnreadable(file.lastPathComponent))
        case let file?: String(localized: .notesWidgetMissing(file.lastPathComponent))
        }
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return Data("<!doctype html><p style=\"color:var(--text-3);font-size:12px;padding:12px\">\(escaped)</p>".utf8)
    }
}
