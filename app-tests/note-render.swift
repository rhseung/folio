import AppKit
import FolioDomain
@testable import Folio

/// Lays a note view out in a window that's never shown, and writes it to `FOLIO_NOTE_RENDER` as a PNG when set.
@MainActor enum NoteRender {
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

    /// Space above the font's ascender and below its descender on the line holding `offset`.
    static func gaps(_ view: NSTextView, at offset: Int) -> (above: CGFloat, below: CGFloat)? {
        guard let manager = view.textLayoutManager, let storage = view.textStorage,
              let location = manager.location(manager.documentRange.location, offsetBy: offset),
              let fragment = manager.textLayoutFragment(for: location), let line = fragment.textLineFragments.first,
              let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont else { return nil }
        let baseline = line.glyphOrigin.y - ((fragment as? NoteFragment)?.raise ?? 0)
        return (baseline - font.ascender, line.typographicBounds.height - baseline + font.descender)
    }

    static func write(_ view: NSView, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FOLIO_NOTE_RENDER"] else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: dir).appending(path: "\(name).png"))
    }
}
