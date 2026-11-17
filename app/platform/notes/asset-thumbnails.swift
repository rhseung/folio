import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import ImageIO
import Observation
import UniformTypeIdentifiers
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 애셋 서랍의 그림과 위젯 썸네일이다. 그림 SVG는 미리보기와 같은 웹 엔진과 노트 색으로, 위젯은 노트 안과 같은 격리된 페이지로
// 그려서 라이트와 다크에서 미리보기와 같게 보인다. 서랍 안에서는 위젯을 돌리지 않으므로 처음 그린 화면을 그림으로 남긴다.
// 그림은 내용 해시와 모양마다 기기의 Caches에 두고, 지워도 다시 그린다.
@MainActor @Observable final class AssetThumbnails {
    enum Source: Hashable {
        case figure(URL)
        case widget(NoteWidget.ID, file: URL)
    }

    struct Request: Hashable {
        let source: Source
        // 파일이 바뀌면 다시 읽도록 열쇠에 넣는다. 내용을 읽는 일은 그릴 때만 한다.
        let modified: Date?
        let noteFolder: URL
        let dark: Bool
        let accent: CourseAccent
    }

    static let shared = AssetThumbnails()

    private(set) var drawn = 0
    @ObservationIgnored private var images: [Request: CGImage] = [:]
    @ObservationIgnored private var failed: Set<Request> = []
    @ObservationIgnored private var queue: [Request] = []
    @ObservationIgnored private var busy = false
    @ObservationIgnored private weak var host: PlatformView?
    @ObservationIgnored private lazy var pages = ThumbnailPages()

    // 웹 뷰는 화면에 보이는 창 안에 있을 때만 그리므로, 서랍이 자기 창 안의 뷰를 빌려 준다.
    func host(in view: PlatformView) {
        host = view
        pump()
    }

    func image(_ request: Request) -> CGImage? {
        _ = drawn
        if let image = images[request] { return image }
        if !failed.contains(request), !queue.contains(request) {
            queue.append(request)
            // 뷰의 body 안에서 불리므로, 웹 뷰를 창에 붙이는 일은 그리기가 끝난 뒤로 미룬다.
            Task { self.pump() }
        }
        return nil
    }

    private func pump() {
        guard !busy, !queue.isEmpty, let host else { return }
        pages.move(to: host)
        guard pages.hosted else { return }
        busy = true
        let request = queue.removeFirst()
        Task {
            if let image = await draw(request) {
                // 한 노트의 서랍은 많아야 수십 장이다. 다른 노트로 가도 남겨 두되, 쌓이지 않게 한도를 둔다.
                if images.count >= 400 { images.removeAll() }
                images[request] = image
            } else {
                failed.insert(request)
            }
            busy = false
            drawn += 1
            pump()
        }
    }

    private func draw(_ request: Request) async -> CGImage? {
        let file =
            switch request.source {
            case .figure(let url): url
            case .widget(_, let url): url
            }
        guard let data = LocalFile.read(file) else { return nil }
        let key = Self.key(request, content: data)
        let cached = Self.folder.appending(path: key + ".png")
        if let image = Self.readPNG(cached) { return image }
        let image: CGImage? =
            switch request.source {
            case .figure: await pages.figure(data, dark: request.dark)
            case .widget(let id, _): await pages.widget(id, noteFolder: request.noteFolder, dark: request.dark, accent: request.accent)
            }
        if let image { Self.writePNG(image, to: cached) }
        return image
    }

    // 모양(노트 색, 위젯 테마와 kit, 그리는 크기)이 바뀌면 열쇠도 바뀐다. 그래서 앱을 고친 뒤에는 옛 그림을 쓰지 않는다.
    private static func key(_ request: Request, content: Data) -> String {
        let look: String
        switch request.source {
        case .figure: look = NoteStyle.variables(accent: .gray)
        case .widget: look = NoteWidgets.themeCSS(request.accent) + NoteWidgetKit.script
        }
        let kind = if case .figure = request.source { "figure" } else { "widget" }
        let content = ContentHash.of(String(bytes: content, encoding: .utf8) ?? content.base64EncodedString())
        let size = "\(Int(ThumbnailPages.canvas.width))x\(Int(ThumbnailPages.canvas.height))"
        return [kind, request.dark ? "dark" : "light", size, String(ContentHash.of(look).prefix(12)), content].joined(separator: "-")
    }

    private static let folder: URL = {
        // 테스트와 미리보기는 이 Mac의 Caches에 쓰지 않는다.
        let base = LocalFolders.isIsolated() ? URL.temporaryDirectory : URL.cachesDirectory.appending(path: "Folio")
        return base.appending(path: "asset-thumbnails", directoryHint: .isDirectory)
    }()

    private static func readPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        // folio:not-an-action 기기의 캐시이고, GIST 폴더 밖이다.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, nil)
        CGImageDestinationFinalize(out)
    }
}

@MainActor private final class ThumbnailPages: NSObject, WKNavigationDelegate {
    private let frame = ThumbnailFrame(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private let figurePage: WKWebView
    private let widgetPage = WidgetPage(size: ThumbnailPages.canvas)
    private var loading: WKNavigation?
    private var loaded: CheckedContinuation<Void, Never>?

    // 길게 누르기 미리보기의 큰 썸네일에서도 흐리지 않은 크기다. 위젯은 좁은 노트 열(390pt)보다 조금 좁게 그려,
    // 타일로 줄여도 첫 화면의 글을 알아볼 수 있게 한다.
    static let canvas = Theme.Size.assetPreview

    var hosted: Bool { frame.window != nil }

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        figurePage = WKWebView(frame: CGRect(origin: .zero, size: Self.canvas), configuration: config)
        super.init()
        figurePage.navigationDelegate = self
        for web in [figurePage, widgetPage.view] {
            Self.keepDrawing(web)
            frame.addSubview(web)
        }
        #if os(macOS)
        frame.wantsLayer = true
        frame.layer?.masksToBounds = true
        #else
        frame.clipsToBounds = true
        #endif
    }

    func move(to view: PlatformView) {
        guard frame.superview !== view else { return }
        frame.removeFromSuperview()
        #if os(macOS)
        view.addSubview(frame, positioned: .below, relativeTo: nil)
        #else
        view.insertSubview(frame, at: 0)
        #endif
    }

    // 그림의 색은 그림 스타일이 정하고 노트 색에서는 바탕(`card`)만 쓰므로 과목 색과 상관없다.
    func figure(_ svg: Data, dark: Bool) async -> CGImage? {
        appear(figurePage, dark: dark)
        let css =
            ":root{color-scheme:light dark}html,body{margin:0;width:100%;height:100%;background:var(--card)}"
            + "body{display:flex;align-items:center;justify-content:center}"
            + "img{display:block;max-width:calc(100% - 32px);max-height:calc(100% - 32px)}"
        let page =
            "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: .gray))\(css)</style></head>"
            + "<body><img id=f src=\"data:image/svg+xml;base64,\(svg.base64EncodedString())\"></body></html>"
        loading = figurePage.loadHTMLString(page, baseURL: nil)
        await withCheckedContinuation { loaded = $0 }
        let ready = try? await figurePage.callAsyncJavaScript(
            """
            const img = document.getElementById("f");
            await img.decode().catch(() => null);
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            return img.naturalWidth > 0;
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard ready as? Bool == true else { return nil }
        return await snapshot(figurePage)
    }

    func widget(_ id: NoteWidget.ID, noteFolder: URL, dark: Bool, accent: CourseAccent) async -> CGImage? {
        widgetPage.appear(dark: dark)
        guard await widgetPage.load(id, noteFolder: noteFolder, accent: accent) else { return nil }
        // 위젯은 불러온 뒤에 그리는 일이 많다(글꼴, 수식 조판, 한 프레임 늦은 차트). 그만큼 기다린 뒤에 찍는다.
        _ = try? await widgetPage.view.callAsyncJavaScript(
            """
            await document.fonts.ready;
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            await new Promise(r => setTimeout(r, 400));
            """, arguments: [:], in: nil, contentWorld: .defaultClient)
        return await snapshot(widgetPage.view)
    }

    private func appear(_ web: WKWebView, dark: Bool) {
        #if os(macOS)
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        #else
        web.overrideUserInterfaceStyle = dark ? .dark : .light
        #endif
    }

    private func snapshot(_ web: WKWebView) async -> CGImage? {
        let config = WKSnapshotConfiguration()
        config.rect = web.bounds
        // 그림을 위해 페이지를 새로 그린다. 화면 갱신을 기다리면 보이지 않을 수도 있는 창을 기다리게 된다.
        config.afterScreenUpdates = false
        guard let image = try? await web.takeSnapshot(configuration: config) else { return nil }
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { done(navigation) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { done(loading) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) { done(navigation) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        done(navigation)
    }

    private func done(_ navigation: WKNavigation?) {
        guard navigation === loading else { return }
        loading = nil
        loaded?.resume()
        loaded = nil
    }

    // WebKit은 창이 가려졌다고 판단하면 페이지를 그리지 않는데, 편집기 창은 자주 일부가 가려진다. 이 페이지는 어차피 보이지
    // 않으므로, 그대로 두면 썸네일이 창이 앞으로 올 때까지 기다린다(`NoteMath`와 같다).
    private static func keepDrawing(_ web: WKWebView) {
        #if os(macOS)
        web.setValue(false, forKey: "drawsBackground")
        let setter = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if web.responds(to: setter), let method = class_getInstanceMethod(type(of: web), setter) {
            typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Set.self)(web, setter, false)
        }
        #else
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        #endif
    }
}

private final class ThumbnailFrame: PlatformView {
    #if os(macOS)
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}
