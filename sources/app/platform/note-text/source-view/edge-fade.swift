import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
final class EdgeFade: NSView {
    private let leading: Bool

    init(leading: Bool) {
        self.leading = leading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.maskedCorners = leading ? [.layerMinXMinYCorner, .layerMinXMaxYCorner] : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let gradient = layer as? CAGradientLayer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gradient.colors = [NoteLook.card.cgColor, NoteLook.card.withAlphaComponent(0).cgColor]
        }
        gradient.startPoint = CGPoint(x: leading ? 0 : 1, y: 0.5)
        gradient.endPoint = CGPoint(x: leading ? 1 : 0, y: 0.5)
    }
}
#endif
