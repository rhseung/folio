import FolioDomain
import JavaScriptCore
import Observation
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 편집 보기의 말풍선과 자동 완성 메뉴의 수식은 미리보기의 KaTeX와 노트 스타일시트로 보이지 않는 페이지에서 그려 그림으로 남긴다. 예전에는 SwiftMath로 그렸는데, 메뉴가 내놓는 명령의 약 5분의
// 1(`\underbrace`, `\boldsymbol`, `align` 등)이 실패하거나 미리보기와 다르게 나왔다. 렌더러가 하나이면 수식은 두 보기에서 같게 보이거나, 두 보기에서 함께 실패한다.
@MainActor @Observable final class NoteMath {
    struct Picture {
        let image: PlatformImage
        let size: CGSize

        func fitted(_ slot: CGSize) -> CGSize {
            guard size.width > 0, size.height > 0 else { return size }
            let scale = min(1, slot.width / size.width, slot.height / size.height)
            return CGSize(width: size.width * scale, height: size.height * scale)
        }
    }

    nonisolated static func edge(_ size: CGFloat) -> CGFloat { ceil(size * 0.25) }

    static let shared = NoteMath()

    private let room: CGFloat

    init(room: CGFloat = 1) {
        self.room = room
    }

    private(set) var drawn = 0
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

    // 페이지는 화면에 보이는 창 안에 있을 때만 그리므로, 수식을 보이는 뷰(편집 보기)가 페이지를 가진다. 첫 말풍선이 웹 프로세스를 기다리지 않도록 처음 요청한 수식에서, 또는 `warm`이면 바로 만든다.
    // 창이 아직 화면에 없는 뷰(열리는 중인 창, 테스트의 창)는 화면에 있는 뷰에서 페이지를 가져가지 않는다.
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

    func picture(
        _ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool, trim: Bool = false,
        ready: (() -> Void)? = nil
    ) -> Picture? {
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
            let result = await page.draw(
                job.source, syntax: job.syntax, display: job.display, size: job.size, dark: job.dark,
                room: job.trim ? room : nil)
            guard current == turn else { return }
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
        // 응답하지 않는 페이지가 그 뒤의 모든 수식을 기다리게 하면 안 되므로, 이 수식은 다음에 다시 요청한다. 페이지가 아직 불러오는 중일 때는 그러지 않는다. 처음 시작할 때 첫 그림을 기다리는 시간의
        // 대부분이 그 불러오기이기 때문이다.
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

@MainActor private final class MathPage: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private let frame: PlatformView
    private var loading: WKNavigation?
    private(set) var loaded = false
    private var onLoad: [CheckedContinuation<Void, Never>] = []

    var hosted: Bool { frame.window != nil }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(
            WKUserScript(
                source: NoteStyle.reader, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: .defaultClient))
        web = WKWebView(frame: CGRect(origin: .zero, size: Self.canvas), configuration: config)
        frame = MathFrame(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        super.init()

        #if os(macOS)
        web.setValue(false, forKey: "drawsBackground")
        // WebKit은 창이 가려졌다고 판단하면 페이지를 그리지 않는데, 편집기 창은 자주 일부가 가려진다. 이 페이지는 어차피 보이지 않으므로, 그대로 두면 요청한 그림이 창이 앞으로 올 때까지 기다린다.
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
        let page =
            "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: .gray))\(NoteStyle.css)\(Self.css)</style></head>"
            + "<body class=\"note\"></body></html>"
        loading = web.loadHTMLString(page, baseURL: nil)
    }

    // 말풍선은 긴 수식을 줄바꿈하지 않고 줄여서 맞추므로, 긴 수식도 한 줄에 놓이도록 충분히 넓게 둔다.
    private static let canvas = CGSize(width: 2400, height: 800)

    private static let css =
        "html,body{background:transparent!important}body.note{margin:0;padding:4em;max-width:none;width:max-content}"
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        load()
    }

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
            // 첫 수식 전에 KaTeX 글꼴을 모두 불러온다. 글꼴은 수식이 처음 필요로 할 때 불러오는데, 글꼴이 아직 불러오는 중에도 `document.fonts.ready`가 끝난 것으로 보였다.
            // 그래서 큰 구분 기호(KaTeX_Size1)가 빈 그림으로 나왔고, 그 그림이 그대로 남았다.
            _ = try? await web.callAsyncJavaScript(
                "await Promise.all([...document.fonts].map(f => f.load().catch(() => null)))",
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
        case unreadable
        case failed
    }

    func draw(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, dark: Bool, room: CGFloat?) async -> Drawn {
        if !loaded { await withCheckedContinuation { onLoad.append($0) } }
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(
            of: ">", with: "&gt;")
        let html = display ? "<div class=\"math display\">\(escaped)</div>" : "<span class=\"math\">\(escaped)</span>"
        // KaTeX의 바깥 상자만이 아니라 모든 부분의 상자를 본다. 높은 악센트나 극한은 바깥 상자 밖으로 나간다. 스크린 리더용 MathML 사본은 빼는데, KaTeX가 이를 1px 상자에 숨기고 내용은
        // 그 상자 밖으로 멀리 나가기 때문이다.
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
        do { answer = try await web.callAsyncJavaScript(script, arguments: arguments, contentWorld: .defaultClient) } catch {
            return .failed
        }
        guard let found = answer as? [NSNumber], found.count == 4 else { return .unreadable }
        let ink = CGRect(x: found[0].doubleValue, y: found[1].doubleValue, width: found[2].doubleValue, height: found[3].doubleValue)
        let margin = room.map { ceil(size * $0) } ?? NoteMath.edge(size)
        let rect = CGRect(x: floor(ink.minX) - margin, y: floor(ink.minY) - margin, width: 0, height: 0)
            .union(CGRect(x: ceil(ink.maxX) + margin, y: ceil(ink.maxY) + margin, width: 0, height: 0))
            .intersection(web.bounds)
        guard rect.width > 0, rect.height > 0 else { return .unreadable }

        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = rect
        // 그림을 위해 페이지를 새로 그린다. 화면 갱신을 기다리면 보이지 않을 수도 있는 창을 기다리게 된다.
        snapshot.afterScreenUpdates = false
        guard let image = try? await web.takeSnapshot(configuration: snapshot) else { return .failed }
        let taken = NoteMath.Picture(image: image, size: rect.size)
        guard room != nil else { return .picture(taken) }
        return .picture(Self.inked(image, size: rect.size) ?? taken)
    }

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
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

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

private final class MathFrame: PlatformView {
    #if os(macOS)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}
