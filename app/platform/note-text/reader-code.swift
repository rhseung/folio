#if os(macOS)
import AppKit
#else
import UIKit
#endif

protocol CodeView: AnyObject {}

/// A code block's lines in a view of their own that scrolls sideways: wrapped, a long line would restart at the
/// box's edge and lose the indent that gives code its shape.
final class CodeAttachment: NSTextAttachment {
    let code: NSAttributedString
    #if os(macOS)
    let view: NSView
    #else
    let view: UIView
    #endif

    /// Its view reaches `inset` past the text on both sides, out to the box's edges, so scrolled code runs under them,
    /// and `below` past its last line, so the scroller sits in the box's padding instead of over that line.
    let inset: CGFloat
    let below: CGFloat

    init(code: NSAttributedString, width: CGFloat, inset: CGFloat, below: CGFloat) {
        self.code = code
        self.inset = inset
        self.below = below
        let made = Self.make(code, width: width, inset: inset, below: below)
        view = made.view
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: .zero, size: CGSize(width: width, height: made.size.height))
        // The view stands where the attachment is, and the attachment draws nothing (by default a file icon).
        #if os(macOS)
        image = NSImage(size: bounds.size, flipped: false) { _ in true }
        #else
        image = UIImage()
        #endif
    }

    required init?(coder: NSCoder) { nil }

    #if os(macOS)
    private static func make(_ code: NSAttributedString, width: CGFloat, inset: CGFloat, below: CGFloat) -> (view: NSView, size: CGSize) {
        let text = NSTextView(usingTextLayoutManager: true)
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: inset, height: 0)
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isHorizontallyResizable = true
        text.textStorage?.setAttributedString(code)
        var used = CGSize.zero
        if let manager = text.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
            used = manager.usageBoundsForTextContainer.size
        }
        let size = CGSize(width: width + inset * 2, height: used.height.rounded(.up))
        text.frame = CGRect(origin: .zero, size: CGSize(width: max(size.width, used.width.rounded(.up) + inset * 2), height: size.height))
        let scroll = SideScrollView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height + below))
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        // The regular scroller is a point taller than the box's padding.
        scroll.horizontalScroller?.controlSize = .small
        scroll.verticalScrollElasticity = .none
        scroll.documentView = text
        return (scroll, size)
    }

    /// Hands up-and-down scrolling to the note, so the pointer resting on code doesn't stop the page.
    private final class SideScrollView: NSScrollView, CodeView {
        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
        }
    }
    #else
    private static func make(_ code: NSAttributedString, width: CGFloat, inset: CGFloat, below: CGFloat) -> (view: UIView, size: CGSize) {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = code
        let used = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width + inset * 2, height: used.height.rounded(.up))
        label.frame = CGRect(origin: CGPoint(x: inset, y: 0), size: CGSize(width: used.width.rounded(.up), height: size.height))
        let scroll = SideScrollView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height + below))
        scroll.contentSize = CGSize(width: label.frame.width + inset * 2, height: size.height)
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(label)
        return (scroll, size)
    }

    private final class SideScrollView: UIScrollView, CodeView {}
    #endif
}

extension CodeAttachment {
    /// Puts each code block's view over its attachment. The text view lays the note out lazily, so a view whose line
    /// isn't laid out yet hides until it is. TextKit 2 is meant to do this through `NSTextAttachmentViewProvider`, but
    /// `NSTextView` never asks for one.
    #if os(macOS)
    static func place(in host: NSView, storage: NSAttributedString, manager: NSTextLayoutManager, origin: CGPoint) {
        var live = Set<ObjectIdentifier>()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let code = value as? CodeAttachment else { return }
            live.insert(ObjectIdentifier(code.view))
            if code.view.superview !== host { host.addSubview(code.view) }
            code.view.frame = frame(of: code, at: range.location, manager: manager, origin: origin) ?? .zero
            code.view.isHidden = code.view.frame.isEmpty
        }
        for view in host.subviews where view is CodeView && !live.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
    }
    #else
    static func place(in host: UIView, storage: NSAttributedString, manager: NSTextLayoutManager, origin: CGPoint) {
        var live = Set<ObjectIdentifier>()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let code = value as? CodeAttachment else { return }
            live.insert(ObjectIdentifier(code.view))
            if code.view.superview !== host { host.addSubview(code.view) }
            code.view.frame = frame(of: code, at: range.location, manager: manager, origin: origin) ?? .zero
            code.view.isHidden = code.view.frame.isEmpty
        }
        for view in host.subviews where view is CodeView && !live.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
    }
    #endif

    private static func frame(of code: CodeAttachment, at index: Int, manager: NSTextLayoutManager, origin: CGPoint) -> CGRect? {
        guard let location = manager.location(manager.documentRange.location, offsetBy: index),
              let fragment = manager.textLayoutFragment(for: location), fragment.state == .layoutAvailable,
              let line = fragment.textLineFragments.first else { return nil }
        let frame = fragment.layoutFragmentFrame, bounds = line.typographicBounds
        let x = origin.x + frame.minX + bounds.minX + line.locationForCharacter(at: line.characterRange.location).x - code.inset
        let y = origin.y + frame.minY + bounds.midY - code.bounds.height / 2
        return CGRect(x: x, y: y, width: code.bounds.width + code.inset * 2, height: code.bounds.height + code.below)
    }
}
