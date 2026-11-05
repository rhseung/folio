import AppKit
import FolioDomain
import FolioMarkdown
import SwiftUI
import Testing
@testable import Folio

/// A note view as the app hosts it: `MarkdownEditor` or `NoteReader` in SwiftUI, in a window that's never shown.
///
/// The note-view checks (`NoteScreenTests`, `NoteLayoutTests`, `NoteClickGridTests`, `NoteHangulTests`) see the views
/// only through this: what's drawn, which view a point hits, where the caret goes, how far the page scrolls. This is
/// the one file that knows they are TextKit 2 text views in an `NSScrollView`. The rewrites (#266 a web view for the
/// preview, #267 a plain source editor) change this file and the reference pictures, and keep the checks.
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

    /// Changed to have SwiftUI update the note view, as any change around it in the app does.
    @Observable final class Pulse {
        var accent = 0
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
            let accent = CourseAccent.presets[pulse.accent % 2].accent
            Group {
                switch kind {
                case .edit:
                    MarkdownEditor(text: text, baseURL: baseURL, math: .latex, insert: $insert, saveFile: { _, _ in nil }, openNote: { _ in })
                case .preview:
                    NoteReader(text: note, baseURL: baseURL, math: .latex)
                }
            }
            .environment(\.accent, accent)
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

    // MARK: The TextKit views

    private var scrollView: NSScrollView? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NoteScrollView { return scroll }
            return view.subviews.lazy.compactMap(find).first
        }
        return find(host)
    }

    private var textView: NSTextView? { scrollView?.documentView as? NSTextView }

    private var widgets: [WidgetWebView] {
        func all(_ view: NSView) -> [WidgetWebView] { ((view as? WidgetWebView).map { [$0] } ?? []) + view.subviews.flatMap(all) }
        return textView.map(all) ?? []
    }

    // MARK: Settling

    /// Lets SwiftUI place the view and the view draw, until what's drawn stops changing.
    func settle() async {
        var last: Pixels?
        for round in 0..<60 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(60))
            guard scrollView != nil, round >= 2 else { continue }
            // A widget's block takes its page's height once the page says it.
            if round < 50, widgets.contains(where: { $0.isLoading || $0.pageHeight == nil }) { continue }
            let now = snapshot()
            if now == last { return }
            last = now
        }
    }

    /// Has SwiftUI update the note view, as a change anywhere around it in the app does: here, the course's color.
    func update() async {
        pulse.accent += 1
        await settle()
    }

    // MARK: Pictures

    /// What the panel shows, without its scrollers, which come and go.
    func snapshot() -> Pixels {
        guard let clip = scrollView?.contentView, clip.bounds.width >= 1, clip.bounds.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(clip.bounds.width), pixelsHigh: Int(clip.bounds.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB)
        else { return blank }
        // One pixel a point whatever the screen, so CI and a Retina Mac make pictures of the same size.
        rep.size = clip.bounds.size
        clip.cacheDisplay(in: clip.bounds, to: rep)
        guard let image = rep.cgImage else { return blank }
        return Pixels(image, page: pageColor)
    }

    /// The whole note, the panel grown to its height.
    func wholeNote() async -> Pixels {
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

    var scrollY: CGFloat { scrollView?.contentView.bounds.minY ?? 0 }

    func scroll(to y: CGFloat) async {
        guard let scroll = scrollView else { return }
        let clip = scroll.contentView
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
        await settle()
    }

    /// As far down as the page goes. TextKit guesses the height of text it hasn't laid out and corrects it as the end
    /// comes into view, so this goes on until a scroll to the end stays where it is.
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

    /// A standard editing action, as a key sends it.
    func perform(_ action: Selector) { _ = input?.tryToPerform(action, with: nil) }

    func focus() { if let input { window.makeFirstResponder(input) } }
}
