import FolioDomain
import WebKit

// 다시 그린 문제 그림(SVG)을 벡터 PDF 한 쪽으로 그린다. 문제집의 TeX이 `\includegraphics`로 넣는다. 비트맵으로 찍으면
// 인쇄에서 글자와 선이 흐려지므로 WebKit의 PDF 출력을 쓴다.
@MainActor
final class FigurePDF: NSObject, WKNavigationDelegate {
    enum Failure: Error { case size, timeout }

    private var loaded: CheckedContinuation<Void, any Error>?

    static func render(_ svg: String) async throws -> Data {
        guard let page = ProblemArt.printPage(svg) else { throw Failure.size }
        let frame = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: frame, configuration: config)
        // 그림의 style은 다크 색을 prefers-color-scheme으로 고르고, 그 값은 뷰의 모양을 따른다.
        // 풀이집은 그림을 회색 상자 안에 넣으므로 바탕을 칠하지 않는다. macOS의 WKWebView는 이 값을 KVC로만 연다.
        #if os(macOS)
        view.appearance = NSAppearance(named: .aqua)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.overrideUserInterfaceStyle = .light
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        let loader = FigurePDF()
        view.navigationDelegate = loader
        // 다 읽지 못한 채 멈추면 문제집 전체가 멈추므로 10초에 끊는다. 이미 읽었으면 `finish`가 아무것도 하지 않는다.
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            loader.finish(Failure.timeout)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            loader.loaded = c
            view.loadHTMLString(page.html, baseURL: nil)
        }
        let pdf = WKPDFConfiguration()
        pdf.rect = frame
        return try await view.pdf(configuration: pdf)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { finish(nil) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) { finish(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        finish(error)
    }

    private func finish(_ error: (any Error)?) {
        guard let loaded else { return }
        self.loaded = nil
        if let error { loaded.resume(throwing: error) } else { loaded.resume() }
    }
}
