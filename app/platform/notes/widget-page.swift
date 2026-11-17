import FolioDomain
import FolioStorage
import WebKit

// 위젯 하나를 창의 페이지로 돌리는 웹 뷰다. 애셋 서랍의 썸네일과 크게 보기가 쓴다. 노트 안의 frame과 같은 scheme, 보안 정책,
// 스크립트(`NoteWidgets.isolate`)를 쓰고, 실행 사이에 아무것도 남기지 않으며, 위젯 페이지 밖으로 가지 못한다. 노트 안의
// 위젯과 상태를 나누지 않으므로 불러올 때마다 처음 상태에서 시작한다.
@MainActor final class WidgetPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private let files = WidgetFiles()
    private var sizer = WidgetSizer()
    private var loading: WKNavigation?
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    var resized: (CGFloat) -> Void = { _ in }

    init(size: CGSize = .zero) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        NoteWidgets.isolate(config.userContentController)
        config.setURLSchemeHandler(files, forURLScheme: WidgetFiles.scheme)
        view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        super.init()
        config.userContentController.add(Reports(self), contentWorld: NoteWidgets.world, name: NoteWidgets.sizeHandler)
        view.navigationDelegate = self
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        #endif
    }

    func appear(dark: Bool) {
        #if os(macOS)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        #else
        view.overrideUserInterfaceStyle = dark ? .dark : .light
        #endif
    }

    // 페이지를 다 불러왔으면 true다. 위젯 파일이 없거나 읽을 수 없으면 `WidgetFiles`가 그 안내를 페이지로 보이므로 그때도 true다.
    @discardableResult func load(_ id: NoteWidget.ID, noteFolder: URL?, accent: CourseAccent) async -> Bool {
        files.folder = noteFolder
        sizer = WidgetSizer()
        waiting.forEach { $0.resume(returning: false) }
        waiting = []
        guard let url = NoteWidgets.url(id, key: id.uuidString, accent: accent) else { return false }
        loading = view.load(URLRequest(url: url))
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func finish(_ navigation: WKNavigation?, _ done: Bool) {
        guard navigation === loading else { return }
        loading = nil
        waiting.forEach { $0.resume(returning: done) }
        waiting = []
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { finish(navigation, true) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) { finish(navigation, false) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        finish(navigation, false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(loading, false) }

    // 위젯은 자기 페이지와 빈 페이지에만 머문다. 다른 주소로 가면 그 주소에 데이터를 실어 내보낼 수 있다.
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url, action.navigationType != .linkActivated else { return decisionHandler(.cancel) }
        decisionHandler(WidgetFiles.allows(url) ? .allow : .cancel)
    }

    fileprivate func report(page: Double, view: Double) {
        if let height = sizer.report(page: page, view: view) { resized(height) }
    }

    // 페이지를 약하게 참조한다. content controller가 처리기를 참조하고 웹 뷰가 controller를 참조하므로, 강하게 참조하면 순환이 생긴다.
    private final class Reports: NSObject, WKScriptMessageHandler {
        weak var page: WidgetPage?
        init(_ page: WidgetPage) { self.page = page }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let h = body["h"] as? Double,
                let v = body["v"] as? Double
            else { return }
            page?.report(page: h, view: v)
        }
    }
}
