import FolioActions
import FolioDomain
import Foundation

enum PageRender {
    static let widths = [480, 900]
    static let tallest = 1800

    static func figurePage(_ svg: String, accent: String) -> String {
        let data = Data(svg.utf8).base64EncodedString()
        return """
            <!doctype html><html><head><meta charset="utf-8"><style>\(theme(accent))\
            body{margin:0}.col{padding:16px}img{display:block;max-width:100%;height:auto;margin:0 auto}</style></head>\
            <body><div class="col"><img src="data:image/svg+xml;base64,\(data)"></div></body></html>
            """
    }

    static func theme(_ accent: String) -> String {
        (NoteTheme.css[accent] ?? NoteTheme.css[CourseColor.neutral] ?? "") + ":where(html){background:var(--card)}"
    }

    static func widgetScripts(accent: String) -> [String] {
        let css = String(decoding: (try? JSONEncoder().encode(theme(accent))) ?? Data(), as: UTF8.self)
        return [
            NoteWidget.noPeersScript,
            "{ const s = document.createElement('style'); s.textContent = \(css); document.documentElement.prepend(s) }",
            NoteWidgetKit.script,
            consoleScript,
        ]
    }

    static let consoleHandler = "folioConsole"

    static let consoleScript = """
        (() => {
          // A stack's first frame says where; its message is not in it.
          const err = e => `${e.name}: ${e.message}` + (e.stack ? ` @ ${e.stack.split('\\n')[0].replace(/^.*@/, '')}` : '')
          const send = (kind, parts) => { try { webkit.messageHandlers.\(consoleHandler).postMessage(kind + ': ' + parts.map(a => {
            try { return a instanceof Error ? err(a) : typeof a === 'object' ? JSON.stringify(a) : String(a) } catch { return String(a) }
          }).join(' ')) } catch {} }
          for (const k of ['error', 'warn']) { const f = console[k]; console[k] = function (...a) { send(k, a); return f.apply(this, a) } }
          addEventListener('error', e => send('error', [e.message + (e.lineno ? ` (line ${e.lineno}:${e.colno})` : '')]))
          addEventListener('unhandledrejection', e => send('error', ['unhandled rejection: ' + (e.reason instanceof Error ? err(e.reason) : e.reason)]))
          document.addEventListener('securitypolicyviolation', e => send('blocked', [`${e.blockedURI} (${e.violatedDirective})`]))
        })()
        """

    // 쓸 때와 같이 마무리한 그림을 그린다.
    static func figure(_ svg: String, accent: String, korean: Bool = false, widths: [Int]) throws -> RenderResult {
        let finished = try NoteFigureFinish.finish(svg, korean: korean)
        let page = figurePage(finished.svg, accent: accent)
        let (images, _) = try shots(page, scripts: [], widths: widths, start: 240, settle: 0.1)
        return RenderResult(images: images, console: [], problems: finished.problems.map(\.message))
    }

    // 다시 그린 문제 그림을 문제집의 TeX이 넣을 벡터 PDF로 그린다. 그리지 못하면 nil이고 문제집은 자른 그림을 쓴다.
    static func figurePDF(_ svg: String) -> Data? {
        #if os(macOS)
        guard Thread.isMainThread, let page = ProblemArt.printPage(svg) else { return nil }
        return MainActor.assumeIsolated { try? OffscreenPage.pdf(page) }
        #else
        return nil
        #endif
    }

    static func widget(_ html: String, accent: String, widths: [Int]) throws -> RenderResult {
        let page = String(decoding: NoteWidget.withPolicy(Data(html.utf8)), as: UTF8.self)
        let (images, console) = try shots(page, scripts: widgetScripts(accent: accent), widths: widths, start: 320, settle: 0.6)
        return RenderResult(
            images: images, console: console, problems: (NoteWidget.problems(html) + NoteWidget.markerProblems(html)).map(\.message))
    }

    static func shots(_ page: String, scripts: [String], widths: [Int], start: Int, settle: TimeInterval) throws -> (
        [RenderedShot], [String]
    ) {
        #if os(macOS)
        // WebKit은 메인 스레드에서 돌고, 그 스레드에서만 run loop가 돈다.
        guard Thread.isMainThread else { throw CLIError(exit: .unexpected, message: String(localized: .renderNotMain)) }
        return try MainActor.assumeIsolated {
            var images: [RenderedShot] = []
            var console: [String] = []
            for width in widths {
                for dark in [false, true] {
                    let shot = try OffscreenPage.shoot(page, scripts: scripts, width: width, dark: dark, start: start, settle: settle)
                    images.append(
                        RenderedShot(theme: dark ? "dark" : "light", width: width, height: shot.height, png: shot.png.base64EncodedString())
                    )
                    for line in shot.console where !console.contains(line) { console.append(line) }
                }
            }
            return (images, console)
        }
        #else
        throw CLIError(exit: .rule, message: String(localized: .renderMacOnly))
        #endif
    }
}

#if os(macOS)
import AppKit
import WebKit

@MainActor
private final class OffscreenPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var loaded = false
    var failure: String?
    var console: [String] = []

    struct Shot {
        var png: Data
        var height: Int
        var console: [String]
    }

    static func shoot(_ page: String, scripts: [String], width: Int, dark: Bool, start: Int, settle: TimeInterval) throws -> Shot {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let handler = OffscreenPage()
        for s in scripts {
            config.userContentController.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        config.userContentController.add(handler, name: PageRender.consoleHandler)
        defer { config.userContentController.removeScriptMessageHandler(forName: PageRender.consoleHandler) }

        let frame = NSRect(x: 0, y: 0, width: width, height: start)
        let view = WKWebView(frame: frame, configuration: config)
        view.navigationDelegate = handler
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.appearance = appearance
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = view
        defer { window.close() }

        // origin 없는 페이지의 오류는 `Script error.`로만 읽히므로 자기 주소를 준다. 그 주소를 서비스하는 것은 없고, 페이지
        // 정책도 아무것도 불러오지 않는다.
        view.loadHTMLString(page, baseURL: OffscreenPage.base)
        guard spin(10, until: { handler.loaded || handler.failure != nil }) else { throw failed(String(localized: .renderTimedOut)) }
        if let failure = handler.failure { throw failed(failure) }
        pause(settle)

        let measured = evaluate(view, "Math.ceil(document.documentElement.getBoundingClientRect().height)") as? Double ?? Double(start)
        let height = min(max(Int(measured), 16), PageRender.tallest)
        window.setContentSize(NSSize(width: width, height: height))
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pause(0.3)

        guard let image = snapshot(view) else { throw failed(String(localized: .renderNoImage)) }
        return Shot(png: try png(image, width: width, height: height), height: height, console: handler.console)
    }

    static func pdf(_ page: ProblemArt.PrintPage) throws -> Data {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let frame = NSRect(x: 0, y: 0, width: page.width, height: page.height)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: frame, configuration: config)
        let handler = OffscreenPage()
        view.navigationDelegate = handler
        // 그림의 style은 다크 색을 prefers-color-scheme으로 고르고, 그 값은 뷰의 모양을 따른다. 인쇄물이라 라이트로 둔다.
        view.appearance = NSAppearance(named: .aqua)
        // 풀이집은 그림을 회색 상자 안에 넣으므로 바탕을 칠하지 않는다. WKWebView는 이 값을 KVC로만 연다.
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(page.html, baseURL: OffscreenPage.base)
        guard spin(10, until: { handler.loaded || handler.failure != nil }) else { throw failed(String(localized: .renderTimedOut)) }
        if let failure = handler.failure { throw failed(failure) }
        let box = Box<Data>()
        let pdf = WKPDFConfiguration()
        pdf.rect = frame
        view.createPDF(configuration: pdf) { result in
            MainActor.assumeIsolated {
                box.value = try? result.get()
                box.done = true
            }
        }
        spin(10) { box.done }
        guard let data = box.value else { throw failed(String(localized: .renderNoImage)) }
        return data
    }

    static let base = URL(string: "folio-render://page/")!

    // 위젯이 주소로 이동하면 그 주소에 데이터를 실어 내보낼 수 있으므로, 여기서 불러온 페이지 하나만 허용한다.
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let url = action.request.url
        decisionHandler(url?.scheme == "about" || url == Self.base ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        failure = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        failure = error.localizedDescription
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // 반복해서 로그를 남기는 위젯이 Claude의 맥락을 채우지 않도록 40줄로 제한한다.
        guard let line = message.body as? String, console.count < 40 else { return }
        console.append(String(line.prefix(600)))
    }

    private static func failed(_ reason: String) -> CLIError {
        CLIError(exit: .unexpected, message: String(localized: .renderFailed(reason)))
    }

    @discardableResult
    private static func spin(_ timeout: TimeInterval, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !done() {
            if Date() > end { return false }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return true
    }

    private static func pause(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        spin(seconds + 1) { Date() >= end }
    }

    @MainActor private final class Box<T> { var value: T?; var done = false }

    private static func evaluate(_ view: WKWebView, _ script: String) -> Any? {
        let box = Box<Any>()
        view.evaluateJavaScript(script) { result, _ in
            MainActor.assumeIsolated {
                box.value = result
                box.done = true
            }
        }
        spin(5) { box.done }
        return box.value
    }

    private static func snapshot(_ view: WKWebView) -> NSImage? {
        let box = Box<NSImage>()
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        view.takeSnapshot(with: config) { image, _ in
            MainActor.assumeIsolated {
                box.value = image
                box.done = true
            }
        }
        spin(10) { box.done }
        return box.value
    }

    // Claude가 읽는 이미지는 픽셀 수로 비용이 들고 두 배 픽셀은 새로 보여 주는 것이 없으므로, 포인트당 1픽셀로 그린다.
    private static func png(_ image: NSImage, width: Int, height: Int) throws -> Data {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else {
            throw failed(String(localized: .renderNoImage))
        }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw failed(String(localized: .renderNoImage)) }
        return data
    }
}
#endif
