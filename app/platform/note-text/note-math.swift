import FolioDomain
import JavaScriptCore
import Observation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Code colors come from npm packages (resources/web/native.js), run in JavaScriptCore with no page, so the code
/// languages stay the ones notes always had.
@MainActor enum NoteScripts {
    private static let helpers: JSValue? = {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(NoteStyle.resource("native.js"))
        return context.objectForKeyedSubscript("folioNative")
    }()

    /// The code block languages the highlighter knows, by the name each is offered under.
    static let languages: [String] = helpers?.objectForKeyedSubscript("languages").call(withArguments: [])?.toArray()?.compactMap { $0 as? String } ?? []

    /// Token spans in UTF-16 offsets of `code`, with the highlighter's classes.
    static func highlight(_ code: String, language: String) -> [(range: NSRange, classes: String)] {
        guard let flat = helpers?.objectForKeyedSubscript("highlight").call(withArguments: [code, language])?.toArray() else { return [] }
        return stride(from: 0, to: flat.count - 2, by: 3).compactMap { i in
            guard let from = flat[i] as? Int, let to = flat[i + 1] as? Int, let cls = flat[i + 2] as? String else { return nil }
            return (NSRange(location: from, length: to - from), cls)
        }
    }
}

/// Math for the edit view's bubble and the completion menu, drawn by the preview's own KaTeX and note stylesheet in a
/// page nobody sees and kept as pictures. SwiftMath drew it before, and about a fifth of the commands the menu offers
/// (`\underbrace`, `\boldsymbol`, `align`, …) failed or came out otherwise than in the preview (#389): with one
/// renderer a formula looks the same in both views, or fails in both.
///
/// Drawing is asynchronous: `picture` returns what is drawn and starts what isn't, and `drawn` changes when it lands,
/// so a SwiftUI view that asked draws again, and `ready` lets an AppKit view ask again.
@MainActor @Observable final class NoteMath {
    struct Picture {
        let image: PlatformImage
        let size: CGSize
    }

    static let shared = NoteMath()

    private(set) var drawn = 0
    /// From the page being made to its first picture, and the last picture's own time; for the PR and the tests.
    @ObservationIgnored private(set) var firstPicture: Duration?
    @ObservationIgnored private(set) var lastPicture: Duration?

    @ObservationIgnored private var cache: [String: Picture] = [:]
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var waiting: [String: [() -> Void]] = [:]
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var current: UUID?
    @ObservationIgnored private var page: MathPage?
    @ObservationIgnored private var made: ContinuousClock.Instant?
    @ObservationIgnored private weak var host: PlatformView?

    private struct Job {
        let key: String
        let source: String
        let syntax: MathSyntax
        let display: Bool
        let size: CGFloat
        let dark: Bool
    }

    /// The page draws only while it is in a window on screen, so the view that shows math (the edit view) carries it.
    /// It is made on the first formula asked for, or now with `warm`, so the first bubble needn't wait for a web process.
    /// A view whose window isn't on screen yet (a window being opened, a test's) doesn't take it from one that is.
    func host(in view: PlatformView, warm: Bool = false) {
        if warm, page == nil { _ = make() }
        if let host, host !== view, Self.shows(host), !Self.shows(view) {
            pump()
            return
        }
        host = view
        page?.move(to: view)
        pump()
    }

    private static func shows(_ view: PlatformView) -> Bool {
        #if os(macOS)
        view.window?.isVisible == true
        #else
        view.window.map { !$0.isHidden } ?? false
        #endif
    }

    func picture(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool, ready: (() -> Void)? = nil) -> Picture? {
        _ = drawn
        let formula = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formula.isEmpty else { return nil }
        let key = "\(syntax.rawValue)|\(display)|\(size)|\(dark)|\(formula)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        if let ready { waiting[key, default: []].append(ready) }
        if !queue.contains(where: { $0.key == key }) {
            queue.append(Job(key: key, source: formula, syntax: syntax, display: display, size: size, dark: dark))
        }
        pump()
        return nil
    }

    private func make() -> MathPage {
        let page = MathPage()
        self.page = page
        made = ContinuousClock.now
        return page
    }

    private func pump() {
        guard !busy, !queue.isEmpty, let host else { return }
        let page = page ?? make()
        page.move(to: host)
        guard page.hosted else { return }
        busy = true
        let job = queue.removeFirst(), turn = UUID(), started = ContinuousClock.now
        current = turn
        Task {
            let picture = await page.draw(job.source, syntax: job.syntax, display: job.display, size: job.size, dark: job.dark)
            guard current == turn else { return }
            if let picture { cache[job.key] = picture } else { failed.insert(job.key) }
            let now = ContinuousClock.now
            lastPicture = now - started
            if firstPicture == nil, let made { firstPicture = now - made }
            finish(job)
        }
        // A page that stopped answering mustn't hold every formula after it; this one is asked again next time. Not
        // while the page is still loading, which on a cold start is the most of the first picture's wait.
        Task {
            repeat { try? await Task.sleep(for: .seconds(5)) } while current == turn && !page.loaded
            guard current == turn else { return }
            finish(job)
        }
    }

    private func finish(_ job: Job) {
        current = nil
        busy = false
        drawn += 1
        waiting.removeValue(forKey: job.key)?.forEach { $0() }
        pump()
    }
}

/// The hidden page: the note stylesheet and the preview's script, one formula at a time, as wide as it runs.
@MainActor private final class MathPage: NSObject, WKNavigationDelegate {
    let web: WKWebView
    /// One point of the hosting view, clipping the page: the page lays out and draws, and nothing of it shows.
    private let frame: PlatformView
    private var loading: WKNavigation?
    private(set) var loaded = false
    private var onLoad: [CheckedContinuation<Void, Never>] = []

    var hosted: Bool { frame.window != nil }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: NoteStyle.reader, injectionTime: .atDocumentEnd,
                                                                forMainFrameOnly: true, in: .defaultClient))
        web = WKWebView(frame: CGRect(origin: .zero, size: Self.canvas), configuration: config)
        frame = MathFrame(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        super.init()
        #if os(macOS)
        web.setValue(false, forKey: "drawsBackground")
        // WebKit stops drawing a page whose window it judges covered, and an editor window often partly is; this page
        // is never seen, and a picture asked for would wait until the window came forward.
        let setter = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if web.responds(to: setter), let method = class_getInstanceMethod(type(of: web), setter) {
            typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Set.self)(web, setter, false)
        }
        frame.wantsLayer = true
        frame.layer?.masksToBounds = true
        #else
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        frame.clipsToBounds = true
        #endif
        frame.addSubview(web)
        web.navigationDelegate = self
        load()
    }

    private func load() {
        let page = "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: .gray))\(NoteStyle.css)\(Self.css)</style></head>"
            + "<body class=\"note\"></body></html>"
        loading = web.loadHTMLString(page, baseURL: nil)
    }

    /// Wide enough that a long formula stays on one line, as the bubble shrinks it to fit rather than wrapping it.
    private static let canvas = CGSize(width: 2400, height: 800)

    // The page is as wide as its formula and has no padding of its own, so the formula's box is where it was measured.
    private static let css = "html,body{background:transparent!important}body.note{margin:0;padding:8px;max-width:none;width:max-content}"
        + "body.note>.math.display{margin:0;overflow:visible}"

    func move(to view: PlatformView) {
        guard frame.superview !== view else { return }
        frame.removeFromSuperview()
        #if os(macOS)
        view.addSubview(frame, positioned: .below, relativeTo: nil)
        #else
        view.insertSubview(frame, at: 0)
        #endif
    }

    // The web process can be ended by the system; the next formula would wait on a page that no longer runs.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        load()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === loading else { return }
        loading = nil
        loaded = true
        onLoad.forEach { $0.resume() }
        onLoad = []
    }

    func draw(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool) async -> NoteMath.Picture? {
        if !loaded { await withCheckedContinuation { onLoad.append($0) } }
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let html = display ? "<div class=\"math display\">\(escaped)</div>" : "<span class=\"math\">\(escaped)</span>"
        // Every part's box, not only KaTeX's outer one: a tall accent or a limit reaches past it.
        let script = """
            const root = document.documentElement, body = document.body;
            root.style.setProperty("--text", color);
            body.dataset.math = syntax;
            body.style.fontSize = size + "px";
            window.folioReader.update(html);
            // Laying out starts KaTeX's fonts loading, which `ready` then waits for.
            body.getBoundingClientRect();
            await document.fonts.ready;
            const box = body.querySelector(".katex-display > .katex") ?? body.querySelector(".katex");
            if (!box || body.querySelector(".math-error")) return null;
            let r = box.getBoundingClientRect(), left = r.left, top = r.top, right = r.right, bottom = r.bottom;
            for (const el of box.querySelectorAll("*")) {
              const q = el.getBoundingClientRect();
              if (q.width === 0 || q.height === 0) continue;
              left = Math.min(left, q.left); top = Math.min(top, q.top); right = Math.max(right, q.right); bottom = Math.max(bottom, q.bottom);
            }
            return [left, top, right - left, bottom - top];
            """
        let color = String(format: "#%06X", dark ? Swatch.text.dark : Swatch.text.light)
        let arguments: [String: Any] = ["html": html, "syntax": syntax.rawValue, "size": Double(size), "color": color]
        guard let found = try? await web.callAsyncJavaScript(script, arguments: arguments, contentWorld: .defaultClient) as? [NSNumber],
              found.count == 4 else { return nil }
        let ink = CGRect(x: found[0].doubleValue, y: found[1].doubleValue, width: found[2].doubleValue, height: found[3].doubleValue)
        // Glyphs reach a little past their boxes (an italic f, a slanted integral), so a quarter em of room around
        // them, in whole points so the picture isn't stretched into its bounds.
        let room = ceil(size / 4)
        let rect = CGRect(x: floor(ink.minX) - room, y: floor(ink.minY) - room, width: 0, height: 0)
            .union(CGRect(x: ceil(ink.maxX) + room, y: ceil(ink.maxY) + room, width: 0, height: 0))
            .intersection(web.bounds)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = rect
        // The page is drawn afresh for the picture; waiting for the screen would wait on a window that may not show.
        snapshot.afterScreenUpdates = false
        guard let image = try? await web.takeSnapshot(configuration: snapshot) else { return nil }
        return NoteMath.Picture(image: image, size: rect.size)
    }
}

/// Over the text's first point; a click there is meant for the text.
private final class MathFrame: PlatformView {
    #if os(macOS)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}
