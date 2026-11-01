#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#endif

/// Type, colors and spacing of the native note views (app/platform/note-text). The Claude panel's web page still takes
/// the same values from web/src/note.css.
enum NoteLook {
    static let body: CGFloat = 16
    /// Leading near 1.78 at the body size.
    static let lineSpacing: CGFloat = 10
    /// The text column, margins included.
    static let measure: CGFloat = 720
    static let margin: CGFloat = 40
    static let paragraphGap: CGFloat = 14
    static let blockGap: CGFloat = 20
    static let boxPadding: CGFloat = 12
    static let boxIndent: CGFloat = 18
    static let listIndent: CGFloat = 24
    static let radius: CGFloat = 12
    static let tint = CGFloat(0.07)

    static func font(_ size: CGFloat, _ weight: PlatformFont.Weight = .regular, italic: Bool = false, mono: Bool = false) -> PlatformFont {
        let base = mono ? PlatformFont.monospacedSystemFont(ofSize: size, weight: weight) : PlatformFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        #if os(macOS)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        #else
        return base.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: size) } ?? base
        #endif
    }

    /// Monospaced type at the same size looks a size or two larger (its letters are a third wider), so the write
    /// view sets it smaller to read as the body does, as GitHub and Notion do.
    static let monoScale = CGFloat(7) / 8
    // Every level but the last two is larger than the body, so each still reads as a heading against it; five and six
    // keep the body size and stand out by weight, six also by gray.
    static let headingSizes: [CGFloat] = [30, 24, 20, 18, 16, 16]
    static let headingWeights: [PlatformFont.Weight] = [.heavy, .bold, .bold, .semibold, .semibold, .semibold]
    static let codeSize = CGFloat(13.5)
    static let labelSize = CGFloat(13)
    static let smallSize = CGFloat(11)

    static let text = Swatch.text.native
    static let text2 = Swatch.textSecondary.native
    static let text3 = Swatch.textTertiary.native
    static let line = Swatch.line.native
    static let lineSoft = Swatch.lineSoft.native
    static let fill = Swatch.fill.native
    static let card = Swatch.card.native
    static let danger = preset("red").accent

    /// `color` at `alpha` over the page, as one opaque color: a translucent tint drawn paragraph by paragraph shows a
    /// seam where two paragraphs meet.
    static func tint(_ color: PlatformColor, _ alpha: CGFloat) -> PlatformColor {
        #if os(macOS)
        return NSColor(name: nil) { appearance in
            var out = color
            appearance.performAsCurrentDrawingAppearance {
                if let c = color.usingColorSpace(.sRGB), let b = card.usingColorSpace(.sRGB) { out = b.blended(withFraction: alpha, of: c) ?? color }
            }
            return out
        }
        #else
        return UIColor { traits in
            var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
            card.resolvedColor(with: traits).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            color.resolvedColor(with: traits).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 + (r2 - r1) * alpha, green: g1 + (g2 - g1) * alpha, blue: b1 + (b2 - b1) * alpha, alpha: 1)
        }
        #endif
    }

    static func preset(_ name: String) -> (accent: PlatformColor, ink: PlatformColor) {
        let a = CourseAccent.presets.first { $0.name == name }?.accent ?? .gray
        return (a.native, a.inkNative)
    }

    /// Callout kinds borrow the course presets, so a theorem is violet in every course; proofs and remarks have no tint.
    static func callout(_ type: String) -> (color: PlatformColor, tinted: Bool) {
        switch type {
        case "definition", "info", "note", "abstract": (preset("blue").accent, true)
        case "theorem", "lemma", "corollary", "proposition": (preset("violet").accent, true)
        case "example", "counterexample", "tip", "summary", "solution": (preset("green").accent, true)
        case "warning", "important", "question": (preset("orange").accent, true)
        case "danger": (danger, true)
        case "proof", "remark": (CourseAccent.gray.native, false)
        default: (CourseAccent.gray.native, true)
        }
    }

    /// Code colors by the highlighter's `tok-*` classes (resources/web/native.js).
    static func token(_ classes: String) -> (color: PlatformColor, italic: Bool)? {
        let set = Set(classes.split(separator: " ").map(String.init))
        // A token carries several classes (a called method is a property and a function), so the first match wins.
        for (names, color, italic) in tokenColors where !set.isDisjoint(with: names) { return (color, italic) }
        return nil
    }

    private static let tokenColors: [(Set<String>, PlatformColor, Bool)] = [
        (["tok-comment"], text3, true),
        (["tok-keyword", "tok-operatorKeyword"], preset("violet").accent, false),
        (["tok-function"], preset("blue").accent, false),
        (["tok-string", "tok-string2"], preset("green").accent, false),
        (["tok-number", "tok-bool", "tok-atom", "tok-literal"], preset("orange").accent, false),
        (["tok-typeName", "tok-className", "tok-namespace", "tok-builtin"], preset("teal").accent, false),
        (["tok-meta", "tok-decorator"], preset("pink").accent, false),
        (["tok-propertyName"], preset("red").accent, false),
    ]
}

extension Swatch {
    var native: PlatformColor { PlatformColor(light: light, dark: dark) }
}

extension CourseAccent {
    var native: PlatformColor { PlatformColor(light: light, dark: dark) }
    var inkNative: PlatformColor { PlatformColor(light: inkLight, dark: inkDark) }
}

extension PlatformColor {
    convenience init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        let (l, d) = (rgb(light), rgb(dark))
        #if os(macOS)
        self.init(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        #else
        self.init { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        }
        #endif
    }
}
