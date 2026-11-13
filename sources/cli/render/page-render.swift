import FolioDomain
import Foundation

struct RenderedShot: Codable, Sendable {
    var theme: String
    var width: Int
    var height: Int
    /// PNG, base64. `folio mcp` hands it to Claude as an image.
    var png: String
}

struct RenderResult: Codable, Sendable {
    var images: [RenderedShot]
    /// The widget's console errors and warnings, and what its policy blocked.
    var console: [String]
    /// What `note figure add` / `note widget add` would refuse.
    var problems: [String]
}

/// Draws note pictures and widgets the way a note shows them, off screen, so Claude can look at what it wrote: words
/// that overlap, parts cut off, colors lost in dark. A command-line program can host `WKWebView` in a window it never
/// shows; the app's panel reaches this through `folio mcp`, so both use the same drawing.
enum PageRender {
    static let widths = [480, 900]
    /// A widget page that grows past this is cut: a taller picture costs Claude more than it shows.
    static let tallest = 1800

    /// The note's padding around a picture, and its rules for one: centered, never wider than the column.
    static func figurePage(_ svg: String, accent: String) -> String {
        let data = Data(svg.utf8).base64EncodedString()
        return """
            <!doctype html><html><head><meta charset="utf-8"><style>\(theme(accent))\
            body{margin:0}.col{padding:16px}img{display:block;max-width:100%;height:auto;margin:0 auto}</style></head>\
            <body><div class="col"><img src="data:image/svg+xml;base64,\(data)"></div></body></html>
            """
    }

    /// The note's colors as a widget's frame gets them, on the note's card, which shows through the frame in the note.
    static func theme(_ accent: String) -> String {
        (NoteTheme.css[accent] ?? NoteTheme.css[CourseColor.neutral] ?? "") + ":where(html){background:var(--card)}"
    }

    /// Before the widget's own code: the theme first, so the widget's styles win, and errors caught from the start.
    static func widgetScripts(accent: String) -> [String] {
        let css = String(decoding: (try? JSONEncoder().encode(theme(accent))) ?? Data(), as: UTF8.self)
        return [
            NoteWidget.noPeersScript,
            "{ const s = document.createElement('style'); s.textContent = \(css); document.documentElement.prepend(s) }",
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

    static func figure(_ svg: String, accent: String, widths: [Int]) throws -> RenderResult {
        let page = figurePage(svg, accent: accent)
        let (images, _) = try shots(page, scripts: [], widths: widths, start: 240, settle: 0.1)
        return RenderResult(images: images, console: [], problems: NoteFigure.problems(svg).map(\.message))
    }

    static func widget(_ html: String, accent: String, widths: [Int]) throws -> RenderResult {
        let page = String(decoding: NoteWidget.withPolicy(Data(html.utf8)), as: UTF8.self)
        // A widget's block starts at 320 points, the height a page sized by its frame keeps.
        let (images, console) = try shots(page, scripts: widgetScripts(accent: accent), widths: widths, start: 320, settle: 0.6)
        return RenderResult(images: images, console: console, problems: NoteWidget.problems(html).map(\.message))
    }

    static func shots(_ page: String, scripts: [String], widths: [Int], start: Int, settle: TimeInterval) throws -> (
        [RenderedShot], [String]
    ) {
        #if os(macOS)
        // WebKit runs on the main thread, and only there does a run loop turn for it.
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
                    // The same page logs the same at every size; each message once.
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
        // No Dock icon and no menu bar: the window is never shown.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let config = WKWebViewConfiguration()
        // Nothing the page stores outlives the drawing.
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

        // An address of its own rather than none: errors from a page with no origin read only "Script error.". Nothing
        // serves it, and the page's policy loads nothing anyway.
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

    static let base = URL(string: "folio-render://page/")!

    /// The page loaded here is the only one: a widget sent to an address would carry data out in it.
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
        // A widget that logs in a loop would otherwise fill Claude's context.
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

    /// At one pixel per point: an image Claude reads costs by its pixels, and twice the pixels show it nothing new.
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
