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

    /// Pictures in a table under column titles, each row named on its left, on the note's card color. A row with a
    /// picture too wide for a column (a formula longer than the line) puts its pictures under one another instead.
    /// Written to `FOLIO_NOTE_RENDER`, or else to `sheets/` in `FOLIO_NOTE_SCREENS`, which CI uploads on every run as
    /// the `note-sheets` artifact: a folder of its own, so `mise run note-screens` doesn't take a sheet for a reference.
    static func sheet(_ rows: [(String, [NSBitmapImageRep])], columns: [String], dark: Bool, _ name: String) {
        let environment = ProcessInfo.processInfo.environment
        guard let dir = environment["FOLIO_NOTE_RENDER"] ?? environment["FOLIO_NOTE_SCREENS"].flatMap({ $0.isEmpty ? nil : "\($0)/sheets" }),
              let scale = rows.first?.1.first.map({ CGFloat($0.pixelsWide) / $0.size.width }) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let gap: CGFloat = 8, labelWidth: CGFloat = 112, titleHeight: CGFloat = 28, widest: CGFloat = 360
        let narrow = rows.filter { $0.1.allSatisfy { $0.size.width <= widest } }
        let column = narrow.flatMap { $0.1 }.map(\.size.width).max() ?? widest
        let table = labelWidth + CGFloat(columns.count) * (column + gap)
        let width = max(table, labelWidth + (rows.flatMap { $0.1 }.map(\.size.width).max() ?? 0)) + gap
        var placed: [(NSBitmapImageRep, CGPoint)] = [], labels: [(String, CGPoint)] = []
        var y = titleHeight
        for (label, cells) in rows {
            labels.append((label, CGPoint(x: gap, y: y + gap)))
            if cells.allSatisfy({ $0.size.width <= widest }) {
                for (i, cell) in cells.enumerated() { placed.append((cell, CGPoint(x: labelWidth + CGFloat(i) * (column + gap), y: y))) }
                y += (cells.map(\.size.height).max() ?? 0) + gap
            } else {
                for cell in cells {
                    placed.append((cell, CGPoint(x: labelWidth, y: y)))
                    y += cell.size.height + gap
                }
            }
        }
        let size = CGSize(width: width, height: y)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        // Before the context is made: it takes the rep's points, and drew at one pixel a point otherwise.
        out.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: out) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Drawn from the top: AppKit's y runs up.
        func flip(_ point: CGPoint, _ height: CGFloat) -> CGPoint { CGPoint(x: point.x, y: size.height - point.y - height) }
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            NoteLook.card.setFill()
            NSRect(origin: .zero, size: size).fill()
            let type: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NoteLook.text2]
            for (i, title) in columns.enumerated() {
                (title as NSString).draw(at: flip(CGPoint(x: labelWidth + CGFloat(i) * (column + gap) + 12, y: gap), 16), withAttributes: type)
            }
            for (label, at) in labels { (label as NSString).draw(at: flip(at, 16), withAttributes: type) }
            for (cell, at) in placed { cell.draw(in: NSRect(origin: flip(at, cell.size.height), size: cell.size)) }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: URL(filePath: dir).appending(path: "\(name).png"))
    }
}
