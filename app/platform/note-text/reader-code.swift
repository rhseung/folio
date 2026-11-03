#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A view the read view put over an attachment, so `AttachedViews.place` knows which subviews are its own.
protocol AttachedView: AnyObject {}

/// An attachment that draws nothing and has a view of its own stand where it is.
protocol ViewAttachment: NSTextAttachment {
    var view: PlatformView { get }
    /// How far the view reaches past the attachment on both sides, and below it.
    var inset: CGFloat { get }
    var below: CGFloat { get }
}

/// A code block's lines in a view of their own that scrolls sideways: wrapped, a long line would restart at the
/// box's edge and lose the indent that gives code its shape.
final class CodeAttachment: NSTextAttachment, ViewAttachment {
    let code: NSAttributedString
    let view: PlatformView

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
        scroll.documentView = text
        return (scroll, size)
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
    #endif
}

/// A formula, table or diagram wider than its room, in a view that scrolls sideways as code does. Left in the text, a
/// line wider than the column has TextKit move the whole page over to keep the line's ends on screen, which cuts off
/// the end of every other line.
final class WidePictureAttachment: NSTextAttachment, ViewAttachment {
    let view: PlatformView
    let inset: CGFloat = 0
    /// Past the picture, so the scroller sits under it instead of over its bottom.
    let below: CGFloat

    init(image: PlatformImage, size: CGSize, descent: CGFloat, width: CGFloat, below: CGFloat) {
        self.below = below
        #if os(macOS)
        // Flipped, so the picture stands at the top of the view and the room for the scroller is under it.
        let document = FlippedView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height + below))
        let picture = NSImageView(frame: CGRect(origin: .zero, size: size))
        picture.image = image
        picture.imageScaling = .scaleNone
        document.addSubview(picture)
        let scroll = SideScrollView(frame: CGRect(x: 0, y: 0, width: width, height: size.height + below))
        scroll.documentView = document
        view = scroll
        #else
        let picture = UIImageView(image: image)
        picture.frame = CGRect(origin: .zero, size: size)
        let scroll = SideScrollView(frame: CGRect(x: 0, y: 0, width: width, height: size.height + below))
        scroll.contentSize = size
        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(picture)
        view = scroll
        #endif
        super.init(data: nil, ofType: nil)
        bounds = CGRect(x: 0, y: -descent, width: width, height: size.height)
        #if os(macOS)
        self.image = NSImage(size: bounds.size, flipped: false) { _ in true }
        #else
        self.image = UIImage()
        #endif
    }

    required init?(coder: NSCoder) { nil }
}

#if os(macOS)
/// Sideways only, with up-and-down scrolling handed to the note, so the pointer resting on code or a picture doesn't
/// stop the page. A click on it falls through to the note under it (`NoteScrollView.hitTest`).
final class SideScrollView: NSScrollView, AttachedView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        // The regular scroller is a point taller than a code box's padding.
        horizontalScroller?.controlSize = .small
        verticalScrollElasticity = .none
    }

    required init?(coder: NSCoder) { nil }

    // A scroll view answers for its document, and code's is a text view, so a click on the code made the window
    // hand this view the keyboard, and the note lost its typing, shortcuts and find bar.
    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
#else
private final class SideScrollView: UIScrollView, AttachedView {}
#endif

/// Puts each attachment's view over it. The text view lays the note out lazily, so a view whose line isn't laid out yet
/// hides until it is. TextKit 2 is meant to do this through `NSTextAttachmentViewProvider`, but `NSTextView` never asks
/// for one.
@MainActor enum AttachedViews {
    static func place(in host: PlatformView, storage: NSAttributedString, manager: NSTextLayoutManager, origin: CGPoint) {
        var live = Set<ObjectIdentifier>()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? any ViewAttachment else { return }
            let view = attachment.view
            live.insert(ObjectIdentifier(view))
            if view.superview !== host { host.addSubview(view) }
            view.frame = frame(of: attachment, at: range.location, manager: manager, origin: origin) ?? .zero
            view.isHidden = view.frame.isEmpty
        }
        for view in host.subviews where view is AttachedView && !live.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
    }

    private static func frame(of attachment: any ViewAttachment, at index: Int, manager: NSTextLayoutManager, origin: CGPoint) -> CGRect? {
        guard let location = manager.location(manager.documentRange.location, offsetBy: index),
              let fragment = manager.textLayoutFragment(for: location), fragment.state == .layoutAvailable,
              let line = fragment.textLineFragments.first else { return nil }
        let frame = fragment.layoutFragmentFrame, bounds = line.typographicBounds
        let x = origin.x + frame.minX + bounds.minX + line.locationForCharacter(at: line.characterRange.location).x - attachment.inset
        let y = origin.y + frame.minY + bounds.midY - attachment.bounds.height / 2
        return CGRect(x: x, y: y, width: attachment.bounds.width + attachment.inset * 2, height: attachment.bounds.height + attachment.below)
    }
}
