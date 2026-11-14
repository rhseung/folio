import FolioDomain
import FolioStorage
import WebKit

// 위젯은 Claude가 쓰거나 사용자가 붙여 넣은 것이라 신뢰할 수 없는 코드로 다룬다. frame은 자기만의 origin으로 sandbox 되어 노트 페이지에 닿거나 페이지를 이동시키지 못한다. 보안 정책은 자기
// 인라인 코드만 돌리고 아무것도 불러오지 못하게 하며, 실행 사이에 아무것도 남지 않고, 다른 페이지로 가지 못한다.
@MainActor final class NoteWidgets {
    let files = WidgetFiles()
    var resized: (String, CGFloat) -> Void = { _, _ in }
    private var accent = CourseAccent.gray
    private var used: [UUID: Int] = [:]
    private var keys: Set<String> = []
    private var sizers: [String: WidgetSizer] = [:]
    private(set) var frames: [String: WKFrameInfo] = [:]

    init(scripts: WKUserContentController) {
        scripts.addUserScript(WKUserScript(source: NoteWidget.noPeersScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        scripts.addUserScript(WKUserScript(source: Self.themeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
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

    var settled: Bool { keys.allSatisfy { sizers[$0]?.height != nil } }

    func frame(for html: String) -> String? {
        guard
            let m = html.wholeMatch(of: /<div class="cb-widget" data-widget="([0-9A-Fa-f-]{36})"(?: style="height:(-?\d+)px")?><\/div>\n?/),
            let id = UUID(uuidString: String(m.1))
        else { return nil }
        let n = used[id, default: 0]
        used[id] = n + 1
        let file = files.folder.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) }
        let stamp = file.flatMap { LocalFile.modified($0) }.map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "none"
        let key = "\(id.uuidString)-\(n)-\(stamp)"
        keys.insert(key)
        // 높이가 없는 블록은 frame을 숨기고, 숨은 페이지는 높이를 알리지 않는다. 페이지가 알린 높이는 여기 쓰지 않고 미리보기의 스크립트가 남긴다. 노트를 다시 보일 때 미리보기가 frame을 그대로
        // 두고 위젯이 계속 돌려면 frame의 HTML이 같아야 하기 때문이다.
        let height = max(m.2.flatMap { Int($0) } ?? 320, 16)
        if sizers[key] == nil { sizers[key] = WidgetSizer() }
        var url = URLComponents()
        url.scheme = WidgetFiles.scheme
        url.host = "widget"
        url.path = "/" + id.uuidString
        // 글자와 숫자 외의 모든 문자를 이스케이프한다. `+`, `&`, `=`를 그대로 두면 테마 값이 갈라지고, 주소는 그대로 속성에 들어간다.
        let encode = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
        url.percentEncodedQueryItems = [
            URLQueryItem(name: "k", value: encode(key)), URLQueryItem(name: "t", value: encode(Self.themeCSS(accent))),
        ]
        let src = url.url?.absoluteString ?? ""
        return
            "<iframe class=\"cb-widget\" sandbox=\"allow-scripts\" data-key=\"\(key)\" data-height=\"\(height)\" src=\"\(src)\"></iframe>\n"
    }

    fileprivate func report(_ key: String, page: Double, view: Double, frame: WKFrameInfo) {
        guard keys.contains(key) else { return }
        frames[key] = frame
        if let height = sizers[key]?.report(page: page, view: view) { resized(key, height) }
    }

    // MARK: Scripts

    private static let world = WKContentWorld.world(name: "folio-widget")

    private final class Reports: NSObject, WKScriptMessageHandler {
        static let name = "size"
        weak var widgets: NoteWidgets?
        init(_ widgets: NoteWidgets) { self.widgets = widgets }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let key = body["k"] as? String, let page = body["h"] as? Double,
                let view = body["v"] as? Double
            else { return }
            widgets?.report(key, page: page, view: view, frame: message.frameInfo)
        }
    }

    // `scrollHeight`가 아니라 루트 요소의 상자를 잰다. `scrollHeight`는 frame보다 작아지지 않아서 커지기만 한다.
    private static let sizeScript = """
        if (location.protocol === '\(WidgetFiles.scheme):') {
          const html = document.documentElement, k = new URLSearchParams(location.search).get('k')
          const report = () => webkit.messageHandlers.\(Reports.name).postMessage({ k, h: html.getBoundingClientRect().height, v: innerHeight })
          new ResizeObserver(report).observe(html); addEventListener('resize', report); report()
        }
        """

    // 위젯의 스타일보다 먼저 노트 페이지가 쓰는 이름으로 노트 색을 넣는다. 블록 안에 두는 이유는 최상위 이름이 위젯 스크립트가 선언한 같은 이름과 충돌하기 때문이다.
    private static let themeScript = """
        if (location.protocol === '\(WidgetFiles.scheme):') {
          const t = new URLSearchParams(location.search).get('t')
          if (t !== null) { const s = document.createElement('style'); s.id = 'folio-theme'; s.textContent = t; document.documentElement.prepend(s) }
        }
        """

    static func themeCSS(_ accent: CourseAccent) -> String {
        NoteStyle.variables(accent: accent)
            + ":root{color-scheme:light dark}"
            + ":where(body){margin:0;font:14px/1.5 -apple-system,system-ui,sans-serif;color:var(--text);background:transparent}"
    }

}

// frame 크기를 따르는 페이지(`100vh`, `50vh`, `calc(600px - 100vh)`)는 frame이 바뀔 때마다 같은 비율로 바뀌므로, 따라가면 끝나지 않는다. 그런 페이지는 처음 보인 높이를
// 유지한다. frame이 따라가는 동안 다시 커지는 내용(글꼴, 그림, 한 프레임 늦게 그린 차트)은 제 나름의 양만큼 바뀌므로, 둘이 한 번 함께 바뀐 것만으로는 구분할 수 없다.
struct WidgetSizer {
    private(set) var height: CGFloat?
    private var last: (page: Double, view: Double)?
    private var start: Double?
    private var share: Double?
    private var followsView = false

    mutating func report(page: Double, view: Double) -> CGFloat? {
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

@MainActor final class WidgetFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-widget"

    var folder: URL?

    static func allows(_ url: URL) -> Bool {
        url.scheme == "about" || (url.scheme == scheme && url.host == "widget")
    }

    private var running = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "widget", let id = UUID(uuidString: url.lastPathComponent) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let file = folder.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) }
        let key = ObjectIdentifier(task as AnyObject)
        running.insert(key)
        Task {
            let read = if let file { await LocalFileScheme.read(file) } else { Data?.none }
            guard running.remove(key) != nil else { return }
            let data = NoteWidget.withPolicy(read ?? Self.notice(file))
            let headers = ["Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": NoteWidget.policy]
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { running.remove(ObjectIdentifier(task as AnyObject)) }

    static func notice(_ file: URL?) -> Data {
        let text =
            switch file {
            case nil: String(localized: .notesWidgetNoCourse)
            case let file? where LocalFile.exists(file): String(localized: .notesWidgetUnreadable(file.lastPathComponent))
            case let file?: String(localized: .notesWidgetMissing(file.lastPathComponent))
            }
        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return Data("<!doctype html><p style=\"color:var(--text-3);font-size:12px;padding:12px\">\(escaped)</p>".utf8)
    }
}
