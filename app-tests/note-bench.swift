import AppKit
import FolioDomain
import FolioMarkdown
import SwiftUI
import Testing
import WebKit
@testable import Folio

/// A note view as the app hosts it: `MarkdownEditor` or `NotePreview` in SwiftUI, in a window that's never shown.
///
/// The note-view checks (`NoteScreenTests`, `NoteLayoutTests`, `NoteClickGridTests`, `NoteHangulTests`) see the views
/// only through this: what's drawn, which view a point hits, where the caret goes, how far the page scrolls. This is
/// the one file that knows the edit view is a TextKit 2 text view in an `NSScrollView` and the preview a web view.
/// A new edit view (as #267 made) changes this file and the reference pictures, and keeps the checks.
///
/// Points are in the panel, from its top left, one pixel a point.
@MainActor final class NoteBench {
    enum Kind: String, CaseIterable, Sendable {
        case edit, preview
    }

    @Observable final class Note {
        var text: String
        init(_ text: String) { self.text = text }
    }

    /// Changed to have SwiftUI update the note view, as any change around it in the app does (a save, the preview
    /// scrolling beside it).
    @Observable final class Pulse {
        var count = 0
    }

    struct Rig: View {
        let kind: Kind
        let text: Binding<String>
        let baseURL: URL?
        let dark: Bool
        let pulse: Pulse
        @State private var insert: String?

        var body: some View {
            // Read here so a new text or pulse updates the view, as the note screen's model does.
            let note = text.wrappedValue
            let count = pulse.count
            Group {
                switch kind {
                case .edit:
                    // `saveFile` names the update it came with, so `update()` can tell SwiftUI handed it to the view.
                    MarkdownEditor(text: text, baseURL: baseURL, math: .latex, insert: $insert, saveFile: { _, _ in "update \(count)" }, openNote: { _ in })
                case .preview:
                    NotePreview(text: note, baseURL: baseURL, math: .latex)
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

    init(_ kind: Kind, text: Binding<String>, width: CGFloat = 900, height: CGFloat = 720, dark: Bool = false, baseURL: URL? = NoteBench.notes) {
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let pulse = Pulse()
        let host = NSHostingView(rootView: Rig(kind: kind, text: text, baseURL: baseURL, dark: dark, pulse: pulse))
        window.contentView = host
        (self.kind, self.dark, self.window, self.host, self.pulse) = (kind, dark, window, host, pulse)
    }

    convenience init(_ kind: Kind, _ text: String, width: CGFloat = 900, height: CGFloat = 720, dark: Bool = false) {
        let note = Note(text)
        self.init(kind, text: Binding(get: { note.text }, set: { note.text = $0 }), width: width, height: height, dark: dark)
        self.note = note
    }

    var size: CGSize { host.bounds.size }

    // MARK: Notes

    static func fixture(_ name: String) -> String {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures/\(name).md")
        return Frontmatter.split((try? String(contentsOf: url, encoding: .utf8)) ?? "").body
    }

    static let allMarkdown = fixture("all-markdown")
    /// Taller than the panel at either width, with a picture, a widget and blocks that scroll sideways.
    static let longNote = fixture("long-note")

    /// A course's `Notes` folder holding the fixtures' pictures and the widgets the notes name, so they're drawn.
    static let notes: URL = {
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures")
        let notes = FileManager.default.temporaryDirectory.appending(path: "note-bench-\(UUID().uuidString)")
            .appending(path: "EC4207 그래프 이론").appending(path: CourseFolder.notes.rawValue)
        let assets = notes.appending(path: "assets")
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: fixtures.appending(path: "assets/sample.png"), to: assets.appending(path: "sample.png"))
        let page = "<!doctype html><div style='height:120px;display:grid;place-items:center;border:2px solid var(--accent);border-radius:12px'>위젯</div>"
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

    /// The preview is drawn in its own process, so what it shows is read while settling and kept for `snapshot`.
    private var shown: (pixels: Pixels, scrollY: CGFloat)?

    // MARK: Settling

    /// Lets SwiftUI place the view and the view draw, until what's drawn stops changing (or a few seconds pass).
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
            // The page has the note, and every widget's frame the height its page said.
            guard let web = preview, round >= 2, round >= 50 || web.page?.settled == true else { continue }
            guard let now = await previewShot(web) else { continue }
            shown = now
            if let last, now.pixels == last.pixels, now.scrollY == last.scrollY { return }
            last = now
        }
    }

    /// What the page shows, without the scroller where one always shows. A snapshot taken without waiting for the
    /// screen: the window is never shown, so the screen never updates.
    private func previewShot(_ web: PreviewWebView) async -> (pixels: Pixels, scrollY: CGFloat)? {
        let read = "return [document.documentElement.clientWidth, innerHeight, scrollY]"
        guard let box = try? await web.callAsyncJavaScript(read, contentWorld: .defaultClient) as? [Double], box.count == 3,
              box[0] >= 1, box[1] >= 1 else { return nil }
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

    /// The snapshot at one pixel a point whatever the screen, so CI and a Retina Mac make pictures of the same size.
    nonisolated private static func pixels(_ image: NSImage, width: Int, height: Int, page: CGColor) -> Pixels? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: Pixels.space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { Pixels($0, page: page) }
    }

    /// Has SwiftUI update the note view, as a change anywhere around it in the app does.
    func update(sourceLocation: SourceLocation = #_sourceLocation) async {
        pulse.count += 1
        await settle()
        if let editor = textView as? SourceTextView, editor.saveFile("", Data()) != "update \(pulse.count)" {
            Issue.record("SwiftUI didn't update the edit view", sourceLocation: sourceLocation)
        }
    }

    // MARK: Pictures

    /// What the panel shows, without its scrollers, which come and go.
    func snapshot() -> Pixels {
        if kind == .preview { return shown?.pixels ?? blank }
        guard let clip = scrollView?.contentView, clip.bounds.width >= 1, clip.bounds.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(clip.bounds.width), pixelsHigh: Int(clip.bounds.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB)
        else { return blank }
        // One pixel a point whatever the screen, so CI and a Retina Mac make pictures of the same size.
        rep.size = clip.bounds.size
        // The caret blinks, so what's drawn would never settle with it.
        let carets = textView?.subviews.filter { $0 is NSTextInsertionIndicator && !$0.isHidden } ?? []
        for caret in carets { caret.isHidden = true }
        clip.cacheDisplay(in: clip.bounds, to: rep)
        for caret in carets { caret.isHidden = false }
        guard let image = rep.cgImage else { return blank }
        return Pixels(image, page: pageColor)
    }

    /// The whole note, the panel grown to its height.
    func wholeNote() async -> Pixels {
        if kind == .preview {
            // Down to the last block and the page's own room below it, not the room it keeps to scroll past the end.
            let read = "const last = document.body.lastElementChild; return last ? last.getBoundingClientRect().bottom + scrollY + 96 : 0"
            guard let web = preview, let bottom = try? await web.callAsyncJavaScript(read, contentWorld: .defaultClient) as? Double else { return blank }
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
        Pixels(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: Pixels.space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!, page: pageColor)
    }

    // MARK: Scrolling

    var scrollY: CGFloat { kind == .preview ? shown?.scrollY ?? 0 : scrollView?.contentView.bounds.minY ?? 0 }

    func scroll(to y: CGFloat) async {
        jump(to: y)
        await settle()
    }

    /// Scrolls without waiting for the view to draw.
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

    /// As far down as the page goes. TextKit guesses the height of text it hasn't laid out and corrects it as the end
    /// comes into view, and the preview's widgets take their height as they load, so this goes on until a scroll to
    /// the end stays where it is.
    func scrollToEnd() async {
        for _ in 0..<10 {
            let before = scrollY
            await scroll(to: 1_000_000)
            if abs(scrollY - before) < 0.5 { return }
        }
    }

    // MARK: Pointer

    enum Hit: Equatable {
        /// The note, or what it shows at that point and handles itself: a widget, a block that scrolls sideways.
        case note
        /// The panel's own scroller.
        case scroller
        case other(String)
    }

    func windowPoint(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: size.height - p.y) }

    private func hitView(at p: CGPoint) -> NSView? { host.hitTest(host.superview?.convert(windowPoint(p), from: nil) ?? windowPoint(p)) }

    func hit(at p: CGPoint) -> Hit {
        guard let view = hitView(at: p) else { return .other("nothing") }
        if kind == .preview {
            // The page handles every point of itself: its widgets, its sideways scrolling and its scroller.
            guard let web = preview else { return .other("no note view") }
            return view === web || view.isDescendant(of: web) ? .note : .other(String(describing: type(of: view)))
        }
        guard let note = textView, let scroll = scrollView else { return .other("no note view") }
        if view === note || view.isDescendant(of: note) { return .note }
        // `NoteScrollView` takes some clicks over the note itself and hands them on to it.
        if view === scroll || view === scroll.contentView { return .note }
        if view is NSScroller, view.superview === scroll { return .scroller }
        return .other(String(describing: type(of: view)))
    }

    /// A plain click as the window delivers it: to the view under the point, with the button already up.
    func click(at p: CGPoint) {
        let point = windowPoint(p)
        guard let view = hitView(at: p),
              let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 0) else { return }
        window.postEvent(up, atStart: true)
        view.mouseDown(with: down)
        // Whatever the view didn't take stays queued for the next click otherwise.
        while let left = window.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { _ = left }
    }

    // MARK: Text input

    /// The edit view's text, as the input method and the window see it; nil in the preview, which takes no typing.
    var input: (NSView & NSTextInputClient)? { kind == .edit ? textView : nil }

    var text: String { input?.attributedString?().string ?? "" }

    /// The caret's place in the text and where it's drawn, in the panel.
    var caret: (location: Int, rect: CGRect)? {
        guard let input else { return nil }
        let selection = input.selectedRange()
        guard selection.length == 0 else { return nil }
        return (selection.location, rect(of: selection))
    }

    /// Where the input method would put its window for `range`, in the panel.
    func rect(of range: NSRange) -> CGRect {
        guard let input else { return .null }
        let screen = input.firstRect(forCharacterRange: range, actualRange: nil)
        let inWindow = window.convertFromScreen(screen)
        return CGRect(x: inWindow.minX, y: size.height - inWindow.maxY, width: inWindow.width, height: inWindow.height)
    }

    func selectAll() { perform(#selector(NSText.selectAll(_:))) }

    /// The caret at `location` with the page left where it is; moving it by key scrolls to it.
    func placeCaret(at location: Int) {
        guard kind == .edit else { return }
        textView?.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// A standard editing action, as a key sends it.
    func perform(_ action: Selector) { _ = input?.tryToPerform(action, with: nil) }

    func focus() { if let input { window.makeFirstResponder(input) } }
}
