import AppKit
import FolioDomain
@testable import Folio

/// Lays a note view out in a window that's never shown, and writes it to `FOLIO_NOTE_RENDER` as a PNG when set.
@MainActor enum NoteRender {
    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures")

    static func host(_ view: NSTextView, width: CGFloat = 900, dark: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let scroll = NoteScrollView(document: view)
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        layout(view)
        return window
    }

    static func layout(_ view: NSTextView) {
        guard let manager = view.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)
        let height = manager.usageBoundsForTextContainer.height + 2 * view.textContainerInset.height
        // TextKit 2 draws only what its scroll view shows, so the window grows to the whole note.
        let size = NSSize(width: view.frame.width, height: max(800, height))
        view.window?.setContentSize(size)
        view.enclosingScrollView?.frame = NSRect(origin: .zero, size: size)
        view.setFrameSize(size)
        // The window's layout pass, which puts code views over their blocks.
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        manager.ensureLayout(for: manager.documentRange)
    }

    /// Where the caret is drawn at `offset`, in the text container.
    static func caret(_ view: NSTextView, at offset: Int) -> CGRect? {
        guard let manager = view.textLayoutManager, let storage = view.textStorage,
              let location = manager.location(manager.documentRange.location, offsetBy: offset) else { return nil }
        var rect: CGRect?
        manager.enumerateTextSegments(in: NSTextRange(location: location), type: .selection, options: .rangeNotRequired) { _, r, _, _ in
            rect = r
            return false
        }
        return rect.map { NoteLines.caret($0, at: offset, in: storage) }
    }

    /// The laid-out line holding `offset`, not the paragraph's first: a paragraph wraps into several.
    static func line(_ view: NSTextView, at offset: Int) -> (fragment: NSTextLayoutFragment, line: NSTextLineFragment)? {
        guard let manager = view.textLayoutManager,
              let location = manager.location(manager.documentRange.location, offsetBy: offset),
              let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let inFragment = offset - manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
        return fragment.textLineFragments.first { NSLocationInRange(inFragment, $0.characterRange) }.map { (fragment, $0) }
    }

    /// Where the text on the line holding `offset` is drawn, its font's ascender to its descender, in the text container.
    static func text(_ view: NSTextView, at offset: Int) -> ClosedRange<CGFloat>? {
        guard let (fragment, line) = Self.line(view, at: offset),
              let font = view.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont else { return nil }
        let baseline = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
        return (baseline - font.ascender)...(baseline - font.descender)
    }

    static func write(_ view: NSView, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FOLIO_NOTE_RENDER"] else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: dir).appending(path: "\(name).png"))
    }
}
