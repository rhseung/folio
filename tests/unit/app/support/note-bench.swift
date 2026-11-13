import AppKit
import FolioDomain
import FolioMarkdown
import SwiftUI
import Testing
import WebKit

@testable import Folio

@MainActor final class NoteBench {
    enum Kind: String, CaseIterable, Sendable {
        case edit, preview
    }

    @Observable final class Note {
        var text: String
        init(_ text: String) { self.text = text }
    }

    @Observable final class Pulse {
        var count = 0
        var anchor: AppLink.Anchor?
    }

    struct Rig: View {
        let kind: Kind
        let text: Binding<String>
        let baseURL: URL?
        let dark: Bool
        let pulse: Pulse
        @State private var insert: String?

        var body: some View {
            let note = text.wrappedValue
            let count = pulse.count
            let anchor = pulse.anchor
            Group {
                switch kind {
                case .edit:
                    MarkdownEditor(
                        text: text, baseURL: baseURL, math: .latex, insert: $insert, saveFile: { _, _ in "update \(count)" },
                        openNote: { _ in },
                        anchor: anchor)
                case .preview:
                    NotePreview(text: note, baseURL: baseURL, math: .latex, anchor: anchor)
                }
            }
            .environment(\.accent, CourseAccent.presets[0].accent)
            .environment(\.colorScheme, dark ? .dark : .light)
        }
    }

    let kind: Kind
    let dark: Bool
    let window: NSWindow
    let host: NSView
    let pulse: Pulse
    private var note: Note?

    init(
        _ kind: Kind, text: Binding<String>, width: CGFloat = 900, height: CGFloat = 720, dark: Bool = false,
        baseURL: URL? = NoteBench.notes,
        anchor: AppLink.Anchor? = nil
    ) {
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: height), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let pulse = Pulse()
        pulse.anchor = anchor
        let host = NSHostingView(rootView: Rig(kind: kind, text: text, baseURL: baseURL, dark: dark, pulse: pulse))
        window.contentView = host
        (self.kind, self.dark, self.window, self.host, self.pulse) = (kind, dark, window, host, pulse)
    }

    convenience init(
        _ kind: Kind, _ text: String, width: CGFloat = 900, height: CGFloat = 720, dark: Bool = false, anchor: AppLink.Anchor? = nil
    ) {
        let note = Note(text)
        self.init(
            kind, text: Binding(get: { note.text }, set: { note.text = $0 }), width: width, height: height, dark: dark, anchor: anchor)
        self.note = note
    }

    var size: CGSize { host.bounds.size }

    var anchor: AppLink.Anchor? {
        get { pulse.anchor }
        set { pulse.anchor = newValue }
    }

    // MARK: Notes

    static func fixture(_ name: String) -> String {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/\(name).md")
        return Frontmatter.split((try? String(contentsOf: url, encoding: .utf8)) ?? "").body
    }

    static let allMarkdown = fixture("all-markdown")
    static let longNote = fixture("long-note")

    static let notes: URL = {
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
        let notes = FileManager.default.temporaryDirectory.appending(path: "note-bench-\(UUID().uuidString)")
            .appending(path: "EC4207 그래프 이론").appending(path: CourseFolder.notes.rawValue)
        let assets = notes.appending(path: "assets")
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: fixtures.appending(path: "assets/sample.png"), to: assets.appending(path: "sample.png"))
        let page =
            "<!doctype html><div style='height:120px;display:grid;place-items:center;border:2px solid var(--accent);border-radius:12px'>위젯</div>"
        for id in ["11111111-2222-3333-4444-555555555555", "22222222-3333-4444-5555-666666666666"] {
            guard let file = UUID(uuidString: id).flatMap({ StandardLayout.widgetFile($0, noteFolder: notes) }) else { continue }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(page.utf8).write(to: file)
        }
        return notes
    }()

    // MARK: The views

    private var scrollView: NSScrollView? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NoteScrollView { return scroll }
            return view.subviews.lazy.compactMap(find).first
        }
        return find(host)
    }

    private var textView: NSTextView? { scrollView?.documentView as? NSTextView }

    private var preview: PreviewWebView? {
        func find(_ view: NSView) -> PreviewWebView? {
            if let web = view as? PreviewWebView { return web }
            return view.subviews.lazy.compactMap(find).first
        }
        return find(host)
    }

    // 미리보기는 별도 프로세스에서 그리므로, 보이는 화면을 settle 중에 읽어 `snapshot`용으로 둔다.
    private var shown: (pixels: Pixels, scrollY: CGFloat)?

    // MARK: Settling

    func settle() async {
        if kind == .preview { return await settlePreview() }
        var last: Pixels?
        for round in 0..<40 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
            guard scrollView != nil, round >= 2 else { continue }
            let now = snapshot()
            if now == last { return }
            last = now
        }
    }

    private func settlePreview() async {
        var last: (pixels: Pixels, scrollY: CGFloat)?
        for round in 0..<60 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
            guard let web = preview, round >= 2, round >= 50 || web.page?.settled == true else { continue }
            guard let now = await previewShot(web) else { continue }
            shown = now
            if let last, now.pixels == last.pixels, now.scrollY == last.scrollY { return }
            last = now
        }
    }

    // 창을 화면에 보이지 않으므로 화면이 갱신되지 않는다. 그래서 화면을 기다리지 않고 스냅숏을 찍는다.
    private func previewShot(_ web: PreviewWebView) async -> (pixels: Pixels, scrollY: CGFloat)? {
        let read = "return [document.documentElement.clientWidth, innerHeight, scrollY]"
        guard let box = try? await web.callAsyncJavaScript(read, contentWorld: .defaultClient) as? [Double], box.count == 3,
            box[0] >= 1, box[1] >= 1
        else { return nil }
        let (width, height) = (Int(box[0]), Int(box[1]))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        config.afterScreenUpdates = false
        let page = pageColor
        let pixels = await withCheckedContinuation { (done: CheckedContinuation<Pixels?, Never>) in
            web.takeSnapshot(with: config) { image, _ in
                done.resume(returning: image.flatMap { Self.pixels($0, width: width, height: height, page: page) })
            }
        }
        return pixels.map { ($0, CGFloat(box[2])) }
    }

    // CI와 Retina Mac이 같은 크기의 그림을 만들도록, 화면과 상관없이 1pt를 1픽셀로 찍는다.
    nonisolated private static func pixels(_ image: NSImage, width: Int, height: Int, page: CGColor) -> Pixels? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: Pixels.space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { Pixels($0, page: page) }
    }

    func update(sourceLocation: SourceLocation = #_sourceLocation) async {
        pulse.count += 1
        await settle()
        if let editor = textView as? SourceTextView, editor.saveFile("", Data()) != "update \(pulse.count)" {
            Issue.record("SwiftUI didn't update the edit view", sourceLocation: sourceLocation)
        }
    }

    // MARK: Pictures

    func snapshot() -> Pixels {
        if kind == .preview { return shown?.pixels ?? blank }
        guard let clip = scrollView?.contentView, clip.bounds.width >= 1, clip.bounds.height >= 1,
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(clip.bounds.width), pixelsHigh: Int(clip.bounds.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB)
        else { return blank }
        // CI와 Retina Mac이 같은 크기의 그림을 만들도록, 화면과 상관없이 1pt를 1픽셀로 찍는다.
        rep.size = clip.bounds.size
        // 캐럿이 깜빡이므로, 캐럿까지 그리면 그림이 안정되지 않는다.
        let carets = textView?.subviews.filter { $0 is NSTextInsertionIndicator && !$0.isHidden } ?? []
        for caret in carets { caret.isHidden = true }
        clip.cacheDisplay(in: clip.bounds, to: rep)
        for caret in carets { caret.isHidden = false }
        guard let image = rep.cgImage else { return blank }
        return Pixels(image, page: pageColor)
    }

    func wholeNote() async -> Pixels {
        if kind == .preview {
            let read = "const last = document.body.lastElementChild; return last ? last.getBoundingClientRect().bottom + scrollY + 96 : 0"
            guard let web = preview, let bottom = try? await web.callAsyncJavaScript(read, contentWorld: .defaultClient) as? Double else {
                return blank
            }
            window.setContentSize(NSSize(width: size.width, height: min(16_000, max(size.height, CGFloat(bottom).rounded(.up)))))
            await settle()
            return snapshot()
        }
        guard let view = textView, let manager = view.textLayoutManager else { return blank }
        manager.ensureLayout(for: manager.documentRange)
        let height = (manager.usageBoundsForTextContainer.height + 2 * view.textContainerInset.height).rounded(.up)
        window.setContentSize(NSSize(width: size.width, height: min(16_000, max(size.height, height))))
        await settle()
        return snapshot()
    }

    var pageColor: CGColor {
        var color = CGColor(gray: 1, alpha: 1)
        window.appearance?.performAsCurrentDrawingAppearance { color = NoteLook.card.cgColor }
        return color
    }

    private var blank: Pixels {
        Pixels(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: Pixels.space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!, page: pageColor)
    }

    // MARK: Scrolling

    var scrollY: CGFloat { kind == .preview ? shown?.scrollY ?? 0 : scrollView?.contentView.bounds.minY ?? 0 }

    func scroll(to y: CGFloat) async {
        jump(to: y)
        await settle()
    }

    func jump(to y: CGFloat) {
        if kind == .preview {
            preview?.callAsyncJavaScript("scrollTo(0, y)", arguments: ["y": y], in: nil, in: .defaultClient)
            return
        }
        guard let scroll = scrollView else { return }
        let clip = scroll.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }

    // TextKit은 배치하지 않은 글의 높이를 추정했다가 끝이 보이면 고치고, 미리보기의 위젯은 불러오면서 높이가 정해진다. 그래서 끝으로 스크롤한 위치가 그대로 남을 때까지 되풀이한다.
    func scrollToEnd() async {
        for _ in 0..<10 {
            let before = scrollY
            await scroll(to: 1_000_000)
            if abs(scrollY - before) < 0.5 { return }
        }
    }

    // MARK: Pointer

    enum Hit: Equatable {
        case note
        case scroller
        case other(String)
    }

    func windowPoint(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: size.height - p.y) }

    private func hitView(at p: CGPoint) -> NSView? { host.hitTest(host.superview?.convert(windowPoint(p), from: nil) ?? windowPoint(p)) }

    func hit(at p: CGPoint) -> Hit {
        guard let view = hitView(at: p) else { return .other("nothing") }
        if kind == .preview {
            guard let web = preview else { return .other("no note view") }
            return view === web || view.isDescendant(of: web) ? .note : .other(String(describing: type(of: view)))
        }
        guard let note = textView, let scroll = scrollView else { return .other("no note view") }
        if view === note || view.isDescendant(of: note) { return .note }
        if view === scroll || view === scroll.contentView { return .note }
        if view is NSScroller, view.superview === scroll { return .scroller }
        return .other(String(describing: type(of: view)))
    }

    func click(at p: CGPoint) {
        let point = windowPoint(p)
        guard let view = hitView(at: p),
            let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1),
            let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0)
        else { return }
        window.postEvent(up, atStart: true)
        view.mouseDown(with: down)
        // 뷰가 받지 않은 이벤트는 그대로 두면 다음 클릭까지 큐에 남는다.
        while let left = window.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { _ = left }
    }

    // MARK: Text input

    var input: (NSView & NSTextInputClient)? { kind == .edit ? textView : nil }

    var text: String { input?.attributedString?().string ?? "" }

    var caret: (location: Int, rect: CGRect)? {
        guard let input else { return nil }
        let selection = input.selectedRange()
        guard selection.length == 0 else { return nil }
        return (selection.location, rect(of: selection))
    }

    func rect(of range: NSRange) -> CGRect {
        guard let input else { return .null }
        let screen = input.firstRect(forCharacterRange: range, actualRange: nil)
        let inWindow = window.convertFromScreen(screen)
        return CGRect(x: inWindow.minX, y: size.height - inWindow.maxY, width: inWindow.width, height: inWindow.height)
    }

    func selectAll() { perform(#selector(NSText.selectAll(_:))) }

    func placeCaret(at location: Int) {
        guard kind == .edit else { return }
        textView?.setSelectedRange(NSRange(location: location, length: 0))
    }

    func perform(_ action: Selector) { _ = input?.tryToPerform(action, with: nil) }

    func focus() { if let input { window.makeFirstResponder(input) } }
}
