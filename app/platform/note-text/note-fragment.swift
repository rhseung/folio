#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// `NoteBox`: a tint (and spine) behind the paragraph, joined with the paragraphs around it in the same box.
    static let noteBox = NSAttributedString.Key("folio.box")
    /// `[NoteBox]`: spines of quotes nested in the paragraph's box, outermost first, each a box indent further in.
    static let noteQuotes = NSAttributedString.Key("folio.quotes")
    /// `NoteBelow`: a picture drawn under the paragraph, in its paragraph spacing, so no text moves for it.
    static let noteBelow = NSAttributedString.Key("folio.below")
    /// A color for a thin rule under the paragraph and a short accent bar on it (a level-2 heading).
    static let noteRule = NSAttributedString.Key("folio.rule")
    /// How far `NoteFragment` draws the paragraph's text above where TextKit lays it, to center it in its line.
    static let noteRaise = NSAttributedString.Key("folio.raise")
    /// How tall the caret stands on the paragraph's lines: its text's, not the whole fixed line's.
    static let noteCaret = NSAttributedString.Key("folio.caret")
}

final class NoteBox: NSObject, @unchecked Sendable {
    let fill: PlatformColor?
    let spine: PlatformColor?
    /// First and last paragraph of the box, which round its corners; `outerTop` and `outerBottom` are the part of their
    /// paragraph spacing outside the box.
    let first: Bool, last: Bool
    let outerTop: CGFloat, outerBottom: CGFloat
    let rounded: Bool
    /// Square corners where the box meets the one above or below (a proof under its theorem).
    let joinsAbove: Bool, joinsBelow: Bool

    init(fill: PlatformColor?, spine: PlatformColor? = nil, first: Bool, last: Bool, outerTop: CGFloat = 0, outerBottom: CGFloat = 0,
         rounded: Bool = false, joinsAbove: Bool = false, joinsBelow: Bool = false) {
        self.fill = fill
        self.spine = spine
        self.first = first
        self.last = last
        self.outerTop = outerTop
        self.outerBottom = outerBottom
        self.rounded = rounded
        self.joinsAbove = joinsAbove
        self.joinsBelow = joinsBelow
    }
}

final class NoteBelow: NSObject, @unchecked Sendable {
    let image: PlatformImage
    let size: CGSize
    let gap: CGFloat
    /// Under the line's start instead of centered.
    let leading: Bool

    init(image: PlatformImage, size: CGSize, gap: CGFloat, leading: Bool = false) {
        self.image = image
        self.size = size
        self.gap = gap
        self.leading = leading
    }

    /// The paragraph spacing that makes room for it.
    var room: CGFloat { gap * 2 + size.height }
}

/// Gives every paragraph a fixed line height with its text centered, as Xcode does. With `lineSpacing` alone TextKit 2
/// sits the text at a line's top and puts the gap above the next line, so the caret is as tall as the font under it on a
/// line with text, a gap taller on an empty one, and tinted boxes look padded more above than below.
enum NoteLines {
    static func fix(_ text: NSMutableAttributedString) {
        let ns = text.string as NSString
        var at = 0
        while at < ns.length {
            let p = ns.paragraphRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(p)
            // The tallest font or picture on the paragraph's lines sets them all, so a code span doesn't shift its line.
            var ascent: CGFloat = 0, descent: CGFloat = 0
            text.enumerateAttributes(in: p) { attributes, _, _ in
                if let font = attributes[.font] as? PlatformFont {
                    ascent = max(ascent, font.ascender)
                    descent = max(descent, -font.descender)
                }
                if let bounds = (attributes[.attachment] as? NSTextAttachment)?.bounds {
                    ascent = max(ascent, bounds.maxY)
                    descent = max(descent, -bounds.minY)
                }
            }
            guard ascent > 0, let style = (text.attribute(.paragraphStyle, at: p.location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle else { continue }
            let natural = ascent + descent
            let height = ((natural + style.lineSpacing) / 2).rounded() * 2
            style.lineSpacing = 0
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            text.addAttribute(.paragraphStyle, value: style, range: p)
            // TextKit 2 sits the baseline on the line's bottom, and `baselineOffset` doesn't move it there: a positive
            // one shortens the line, a negative one moves the reported glyph origin but not the drawn text.
            let raise = (height - descent).rounded() - (height + ascent - descent) / 2
            text.addAttribute(.noteRaise, value: (raise * 2).rounded() / 2, range: p)
            text.addAttribute(.noteCaret, value: natural.rounded(), range: p)
        }
    }

    /// The text view's caret is the whole line once its height is fixed, a gap taller than the text it stands in.
    static func caret(_ rect: CGRect, at offset: Int, in text: NSAttributedString) -> CGRect {
        guard text.length > 0, let height = text.attribute(.noteCaret, at: min(offset, text.length - 1), effectiveRange: nil) as? CGFloat,
              height < rect.height else { return rect }
        return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }
}

/// Whether two stylings of the same text look the same. Each styling makes its own colors and boxes, which aren't
/// equal as objects, so they're compared by what they draw.
enum NoteAttributes {
    static func same(_ a: NSAttributedString, _ b: NSAttributedString, in range: NSRange) -> Bool {
        var i = range.location
        while i < NSMaxRange(range) {
            var ra = NSRange(), rb = NSRange()
            let x = a.attributes(at: i, effectiveRange: &ra), y = b.attributes(at: i, effectiveRange: &rb)
            guard same(x, y) else { return false }
            i = min(NSMaxRange(ra), NSMaxRange(rb))
        }
        return true
    }

    static func same(_ x: [NSAttributedString.Key: Any], _ y: [NSAttributedString.Key: Any]) -> Bool {
        x.count == y.count && x.allSatisfy { key, value in y[key].map { same(value, $0) } ?? false }
    }

    static func same(_ x: Any?, _ y: Any?) -> Bool {
        switch (x, y) {
        case (nil, nil): return true
        case let (a as PlatformColor, b as PlatformColor): return a === b || a.cgColor == b.cgColor
        case let (a as NoteBox, b as NoteBox):
            return same(a.fill, b.fill) && same(a.spine, b.spine) && a.first == b.first && a.last == b.last && a.outerTop == b.outerTop
                && a.outerBottom == b.outerBottom && a.rounded == b.rounded && a.joinsAbove == b.joinsAbove && a.joinsBelow == b.joinsBelow
        case let (a as NoteBelow, b as NoteBelow):
            return a.image === b.image && a.size == b.size && a.gap == b.gap && a.leading == b.leading
        case let (a as NSObject, b as NSObject): return a.isEqual(b)
        default: return false
        }
    }
}

/// Draws what TextKit doesn't: box tints behind paragraphs and pictures under them. Kept to drawing, so the text keeps
/// the place its paragraph style gives it.
final class NoteFragment: NSTextLayoutFragment, @unchecked Sendable {
    private var box: NoteBox?
    private var quotes: [NoteBox] = []
    private var spacing: CGFloat = 0
    private(set) var raise: CGFloat = 0
    private var below: NoteBelow?
    private var rule: PlatformColor?
    private var accent: PlatformColor?

    init(element: NSTextElement, range: NSTextRange?, accent: PlatformColor?) {
        super.init(textElement: element, range: range)
        self.accent = accent
        guard let text = (element as? NSTextParagraph)?.attributedString, text.length > 0 else { return }
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        box = attributes[.noteBox] as? NoteBox
        quotes = attributes[.noteQuotes] as? [NoteBox] ?? []
        spacing = (attributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing ?? 0
        raise = attributes[.noteRaise] as? CGFloat ?? 0
        below = attributes[.noteBelow] as? NoteBelow
        rule = attributes[.noteRule] as? PlatformColor
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private var width: CGFloat { textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width }

    /// In the fragment's own coordinates, across the whole column.
    var boxRect: CGRect? {
        guard let box else { return nil }
        let frame = layoutFragmentFrame
        let top = box.first ? box.outerTop : 0
        // TextKit leaves the spacing off the note's last paragraph, and the box's bottom padding is part of it.
        let height = max(frame.height, (textLineFragments.last?.typographicBounds.maxY ?? 0) + spacing)
        // TextKit leaves a sliver between paragraph fragments; a box that goes on reaches over it.
        let bottom = height + (box.last ? -box.outerBottom : 1)
        return CGRect(x: -frame.minX, y: top, width: width, height: max(0, bottom - top))
    }

    private var belowRect: CGRect? {
        guard let below, let last = textLineFragments.last else { return nil }
        let x = below.leading ? 0 : (width - below.size.width) / 2 - layoutFragmentFrame.minX
        return CGRect(x: x, y: last.typographicBounds.maxY + below.gap, width: below.size.width, height: below.size.height)
    }

    override var renderingSurfaceBounds: CGRect {
        [boxRect, belowRect].compactMap { $0 }.reduce(super.renderingSurfaceBounds) { $0.union($1) }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let box, let rect = boxRect {
            let r = rect.offsetBy(dx: point.x, dy: point.y)
            context.saveGState()
            if box.rounded {
                let radius = NoteLook.radius
                let path = CGMutablePath()
                let tr = box.first && !box.joinsAbove ? radius : 0, br = box.last && !box.joinsBelow ? radius : 0
                // A rounded corner would bite into the spine, so the spine's side stays square.
                let tl = box.spine == nil ? tr : 0, bl = box.spine == nil ? br : 0
                path.move(to: CGPoint(x: r.minX, y: r.minY + tl))
                path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
                path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
                path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
                path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
                path.closeSubpath()
                context.addPath(path)
                context.clip()
            }
            if let fill = box.fill {
                context.setFillColor(fill.cgColor)
                context.fill(r)
            }
            if let spine = box.spine {
                context.setFillColor(spine.cgColor)
                context.fill(CGRect(x: r.minX, y: r.minY, width: 4, height: r.height))
            }
            context.restoreGState()
            let lines = textLineFragments
            for (i, quote) in quotes.enumerated() {
                guard let spine = quote.spine else { continue }
                // A nested quote's spine starts and ends with its text, not in the gaps around it.
                let top = quote.first ? (lines.first?.typographicBounds.minY ?? 0) - 2 : 0
                let bottom = quote.last ? (lines.last?.typographicBounds.maxY ?? rect.maxY) + 2 : rect.maxY
                context.setFillColor(spine.cgColor)
                context.fill(CGRect(x: point.x + rect.minX + CGFloat(i + 1) * NoteLook.boxIndent, y: point.y + top, width: 4, height: max(0, bottom - top)))
            }
        }
        super.draw(at: CGPoint(x: point.x, y: point.y - raise), in: context)
        if let rule, let last = textLineFragments.last {
            let y = point.y + last.typographicBounds.maxY + 8
            let x = point.x - layoutFragmentFrame.minX
            context.setFillColor(rule.cgColor)
            context.fill(CGRect(x: x, y: y, width: width, height: 1))
            if let accent {
                context.setFillColor(accent.cgColor)
                context.fill(CGRect(x: x, y: y - 0.5, width: 28, height: 2))
            }
        }
        if let below, let rect = belowRect {
            draw(below.image, in: rect.offsetBy(dx: point.x, dy: point.y), context: context)
        }
    }

    private func draw(_ image: PlatformImage, in rect: CGRect, context: CGContext) {
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        image.draw(in: rect)
        UIGraphicsPopContext()
        #endif
    }
}

/// Hands TextKit `NoteFragment`s, for both note views.
final class NoteLayout: NSObject, NSTextLayoutManagerDelegate {
    var accent: PlatformColor?

    func textLayoutManager(_ manager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in element: NSTextElement) -> NSTextLayoutFragment {
        NoteFragment(element: element, range: element.elementRange, accent: accent)
    }
}
