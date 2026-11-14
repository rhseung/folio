import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
final class PreviewBubble: NSView {
    static let pad = Theme.Space.m
    static let fade = 2 * Theme.Space.xl

    let picture: NSImageView
    let scroller: BubbleScroller
    let leading = EdgeFade(leading: true), trailing = EdgeFade(leading: false)
    var hovered = false
    var onLeave: (() -> Void)?
    let scrolls: Bool

    init(image: NSImage, size: CGSize, width: CGFloat) {
        let pad = Self.pad, border: CGFloat = 1
        let whole = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let shown = CGSize(width: min(whole.width, max(width, 2 * pad)), height: whole.height)
        let inner = NSRect(origin: .zero, size: shown).insetBy(dx: border, dy: border)
        picture = NSImageView(frame: NSRect(origin: CGPoint(x: pad - border, y: pad - border), size: size))
        scroller = BubbleScroller(frame: inner)
        scrolls = whole.width > shown.width
        super.init(frame: NSRect(origin: .zero, size: shown))

        wantsLayer = true
        layer?.cornerRadius = NoteLook.radius
        layer?.borderWidth = border
        shadow = NSShadow()
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        picture.image = image
        picture.imageScaling = .scaleAxesIndependently
        let document = NSView(frame: NSRect(x: 0, y: 0, width: whole.width - 2 * border, height: inner.height))
        document.addSubview(picture)
        scroller.documentView = document
        scroller.drawsBackground = false
        scroller.hasHorizontalScroller = false
        scroller.hasVerticalScroller = false
        scroller.verticalScrollElasticity = .none
        scroller.horizontalScrollElasticity = scrolls ? .automatic : .none
        scroller.wantsLayer = true
        scroller.layer?.cornerRadius = NoteLook.radius - border
        scroller.layer?.masksToBounds = true
        addSubview(scroller)
        scroller.tile()

        for (fade, x) in [(leading, inner.minX), (trailing, inner.maxX - Self.fade)] {
            fade.frame = NSRect(x: x, y: inner.minY, width: Self.fade, height: inner.height)
            fade.layer?.cornerRadius = NoteLook.radius - border
            addSubview(fade)
        }

        scroller.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroller.contentView)
        scrolled()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reveal(_ fraction: CGFloat, line: CGFloat? = nil) {
        guard scrolls, let document = scroller.documentView else { return }
        let visible = scroller.bounds.width
        let across = { (f: CGFloat) in self.picture.frame.minX + f * self.picture.frame.width }
        var x = across(fraction) - visible / 2
        if let line, across(fraction) <= across(line) + visible - 2 * Self.fade { x = across(line) - Self.fade }
        x = min(max(0, x), document.frame.width - visible)
        scroller.contentView.scroll(to: NSPoint(x: x.rounded(), y: 0))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    @objc private func scrolled() {
        let x = scroller.contentView.bounds.minX, end = (scroller.documentView?.frame.width ?? 0) - scroller.bounds.width
        leading.isHidden = !scrolls || x <= 0.5
        trailing.isHidden = !scrolls || x >= end - 0.5
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        scrolls && frame.contains(point) ? scroller : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseMoved(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { left() }

    func left() {
        guard hovered else { return }
        hovered = false
        onLeave?()
    }

    override var wantsUpdateLayer: Bool { true }

    // layer는 고정된 CGColor를 가진다. 여기서 뷰 자신의 appearance로 풀어야 테마가 바뀔 때 따라간다. init에서 풀면 그때의 appearance를 따라서, 라이트 창에 다크 말풍선이 떴다.
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteLook.card.cgColor
            layer?.borderColor = NoteLook.lineSoft.cgColor
        }
    }
}
#endif
