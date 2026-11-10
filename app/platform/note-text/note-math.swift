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

    /// How far past KaTeX's boxes a trimmed picture's snapshot reaches, in ems, before it's cut to its ink: a glyph's
    /// ink runs past its box (an italic f, a slanted integral) by less than one. A test draws with more to see nothing's cut.
    private let room: CGFloat

    init(room: CGFloat = 1) {
        self.room = room
    }

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
        let trim: Bool
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

    /// `trim` cuts the picture to its ink, for the bubble, which pads it evenly. Untrimmed it keeps KaTeX's boxes, the
    /// line box and strut: the palette and the completion menu center a symbol in its cell, and only the boxes keep
    /// `\ldots` under `\cdots`, `.` under `\cdot` and `,` under `'`.
    func picture(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool, trim: Bool = false,
                 ready: (() -> Void)? = nil) -> Picture? {
        _ = drawn
        let formula = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formula.isEmpty else { return nil }
        let key = "\(syntax.rawValue)|\(display)|\(size)|\(dark)|\(trim)|\(formula)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        if let ready { waiting[key, default: []].append(ready) }
        if !queue.contains(where: { $0.key == key }) {
            queue.append(Job(key: key, source: formula, syntax: syntax, display: display, size: size, dark: dark, trim: trim))
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
            let result = await page.draw(job.source, syntax: job.syntax, display: job.display, size: job.size, dark: job.dark,
                                         room: job.trim ? room : nil)
            guard current == turn else { return }
            // Only what KaTeX can't read is given up on; a page that ended or a snapshot that failed is asked again.
            switch result {
            case .picture(let picture): cache[job.key] = picture
            case .unreadable: failed.insert(job.key)
            case .failed: break
            }
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

    // The page is as wide as its formula, with room around it for the snapshot's (`NoteMath.room`): a snapshot past the
    // page's edge is cut there, and an ink running into it would be too.
    private static let css = "html,body{background:transparent!important}body.note{margin:0;padding:4em;max-width:none;width:max-content}"
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

    // Loading a string hardly fails, but if it did every formula would wait on the page for good.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if navigation === loading { load() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if navigation === loading { load() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === loading else { return }
        let finished = navigation
        Task {
            // Every KaTeX font before the first formula. A font loads when a formula first needs it, and
            // `document.fonts.ready` was seen settled while it still loaded: a big delimiter's (KaTeX_Size1) came out
            // blank, and that picture was kept.
            _ = try? await web.callAsyncJavaScript("await Promise.all([...document.fonts].map(f => f.load().catch(() => null)))",
                                                   arguments: [:], in: nil, contentWorld: .defaultClient)
            guard finished === loading else { return }
            loading = nil
            loaded = true
            onLoad.forEach { $0.resume() }
            onLoad = []
        }
    }

    enum Drawn {
        case picture(NoteMath.Picture)
        /// KaTeX can't read it; drawing it again gives the same.
        case unreadable
        case failed
    }

    /// With `room`, the snapshot reaches that many ems past the boxes and is cut to its ink; without, it's the boxes.
    func draw(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool, room: CGFloat?) async -> Drawn {
        if !loaded { await withCheckedContinuation { onLoad.append($0) } }
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let html = display ? "<div class=\"math display\">\(escaped)</div>" : "<span class=\"math\">\(escaped)</span>"
        // Every part's box, not only KaTeX's outer one: a tall accent or a limit reaches past it. Not the MathML copy
        // for screen readers, which KaTeX hides in a 1px box its contents run far out of.
        let script = """
            const root = document.documentElement, body = document.body;
            root.style.setProperty("--text", color);
            body.dataset.math = syntax;
            body.style.fontSize = size + "px";
            window.folioReader.update(html);
            // The page loads every font first; one that is loading again anyway is waited for itself, not by
            // `document.fonts.ready`, which can settle before it has.
            body.getBoundingClientRect();
            for (let loading; (loading = [...document.fonts].filter(f => f.status === "loading")).length;) {
              await Promise.all(loading.map(f => f.loaded.catch(() => null)));
              body.getBoundingClientRect();
            }
            const box = body.querySelector(".katex-display > .katex") ?? body.querySelector(".katex");
            if (!box || body.querySelector(".math-error")) return null;
            let r = box.getBoundingClientRect(), left = r.left, top = r.top, right = r.right, bottom = r.bottom;
            for (const el of box.querySelectorAll("*")) {
              // A stretched brace or arrow is a 400em picture its box clips to the formula's width.
              if (el.closest("svg, .katex-mathml")) continue;
              const q = el.getBoundingClientRect();
              if (q.width === 0 || q.height === 0) continue;
              left = Math.min(left, q.left); top = Math.min(top, q.top); right = Math.max(right, q.right); bottom = Math.max(bottom, q.bottom);
            }
            return [left, top, right - left, bottom - top];
            """
        let color = String(format: "#%06X", dark ? Swatch.text.dark : Swatch.text.light)
        let arguments: [String: Any] = ["html": html, "syntax": syntax.rawValue, "size": Double(size), "color": color]
        let answer: Any?
        do { answer = try await web.callAsyncJavaScript(script, arguments: arguments, contentWorld: .defaultClient) } catch { return .failed }
        guard let found = answer as? [NSNumber], found.count == 4 else { return .unreadable }
        let ink = CGRect(x: found[0].doubleValue, y: found[1].doubleValue, width: found[2].doubleValue, height: found[3].doubleValue)
        // Untrimmed, glyphs still reach a little past their boxes, so a quarter em of room around them; in whole
        // points either way, so the picture isn't stretched into its bounds.
        let margin = ceil(size * (room ?? 0.25))
        let rect = CGRect(x: floor(ink.minX) - margin, y: floor(ink.minY) - margin, width: 0, height: 0)
            .union(CGRect(x: ceil(ink.maxX) + margin, y: ceil(ink.maxY) + margin, width: 0, height: 0))
            .intersection(web.bounds)
        guard rect.width > 0, rect.height > 0 else { return .unreadable }
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = rect
        // The page is drawn afresh for the picture; waiting for the screen would wait on a window that may not show.
        snapshot.afterScreenUpdates = false
        guard let image = try? await web.takeSnapshot(configuration: snapshot) else { return .failed }
        let taken = NoteMath.Picture(image: image, size: rect.size)
        guard room != nil else { return .picture(taken) }
        // Spacing or `\left.` alone has no ink; its picture stays as it was taken, empty.
        return .picture(Self.inked(image, size: rect.size) ?? taken)
    }

    /// The picture cut to the pixels its ink covers, in whole points so it isn't stretched into its frame. KaTeX's
    /// boxes aren't its ink: the line box and the strut reach over and under it, and a picture cut to them had more
    /// room at the top than the sides, which the bubble's even padding then added to.
    private static func inked(_ image: PlatformImage, size: CGSize) -> NoteMath.Picture? {
        #if os(macOS)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let cg = image.cgImage else { return nil }
        #endif
        let (w, h) = (cg.width, cg.height)
        guard w > 0, h > 0, size.width > 0 else { return nil }
        let scale = CGFloat(w) / size.width
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // The page is transparent, so any alpha is ink, its antialiased edge included. Rows run from the top.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where pixels[(row + x) * 4 + 3] > 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let points = CGRect(x: floor(CGFloat(minX) / scale), y: floor(CGFloat(minY) / scale), width: 0, height: 0)
            .union(CGRect(x: ceil(CGFloat(maxX + 1) / scale), y: ceil(CGFloat(maxY + 1) / scale), width: 0, height: 0))
        let crop = CGRect(x: points.minX * scale, y: points.minY * scale, width: points.width * scale, height: points.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cut = cg.cropping(to: crop) else { return nil }
        let cutSize = CGSize(width: CGFloat(cut.width) / scale, height: CGFloat(cut.height) / scale)
        #if os(macOS)
        return NoteMath.Picture(image: NSImage(cgImage: cut, size: cutSize), size: cutSize)
        #else
        return NoteMath.Picture(image: UIImage(cgImage: cut, scale: scale, orientation: .up), size: cutSize)
        #endif
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
