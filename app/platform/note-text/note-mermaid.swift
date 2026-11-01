import BeautifulMermaid
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A ```` ```mermaid ```` block drawn by BeautifulMermaid (native layout, no web view), kept by its source and look.
@MainActor enum NoteMermaid {
    static let language = "mermaid"

    private static var cache: [String: (image: PlatformImage, size: CGSize)] = [:]
    private static var failed: Set<String> = []

    /// Nil when the diagram doesn't parse; the caller shows the source as code instead.
    static func picture(_ source: String, accent: PlatformColor, dark: Bool, width: CGFloat) -> (image: PlatformImage, size: CGSize)? {
        let key = "\(dark)|\(width)|\(NoteMath.resolve(accent, dark: dark))|\(source)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        let color = { NoteMath.resolve($0, dark: dark) }
        let theme = DiagramTheme(background: color(NoteLook.card), foreground: color(NoteLook.text), line: color(NoteLook.text3),
                                 accent: color(accent), muted: color(NoteLook.text2), surface: color(NoteLook.fill), border: color(NoteLook.line),
                                 font: NoteLook.font(NoteLook.labelSize), transparent: true)
        #if os(macOS)
        // Drawn from the laid-out diagram whenever it's shown, so it's sharp at any scale: a bitmap of the diagram's
        // fractional size gets resampled into a blur. The flipped image also gives the renderer the top-down
        // coordinates it expects.
        guard let prepared = try? MermaidImageRenderer(theme: theme).prepare(from: source), prepared.bounds.width > 1 else {
            failed.insert(key)
            return nil
        }
        let bounds = prepared.bounds
        nonisolated(unsafe) let draw = prepared.render
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            guard let current = NSGraphicsContext.current else { return false }
            let context = current.cgContext
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            // Its labels undo the flip themselves and then draw through AppKit, which must not flip them back.
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            draw(context, bounds)
            NSGraphicsContext.current = current
            return true
        }
        #else
        guard let image = try? MermaidRenderer.renderImage(source: source, theme: theme, scale: 3), image.size.width > 1 else {
            failed.insert(key)
            return nil
        }
        #endif
        let result = (image, NoteImages.fit(image.size, alt: "", width: width))
        cache[key] = result
        return result
    }
}
