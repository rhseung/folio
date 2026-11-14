#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
typealias PlatformView = UIView
#endif

// 편집 보기(app/platform/note-text)는 이 값을 그대로 쓰고, 페이지(미리보기, Claude 패널)는 `NoteStyle`을 거쳐 CSS
// 변수로 받는다.
enum NoteLook {
    static let body: CGFloat = 16
    static let lineSpacing: CGFloat = 10
    static let measure: CGFloat = 720
    static let margin: CGFloat = 40
    static let paragraphGap: CGFloat = 14
    static let blockGap: CGFloat = 20
    static let listIndent: CGFloat = 24
    static let radius: CGFloat = 12
    static let breakDot: CGFloat = 4
    static let breakDotPitch: CGFloat = 16
    static let breakSpace: CGFloat = 32

    static func font(_ size: CGFloat, _ weight: PlatformFont.Weight = .regular, italic: Bool = false, mono: Bool = false) -> PlatformFont {
        let base =
            mono ? PlatformFont.monospacedSystemFont(ofSize: size, weight: weight) : PlatformFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }
        #if os(macOS)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        #else
        return base.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: size) } ?? base
        #endif
    }

    // 같은 크기의 고정폭 글꼴은 글자 폭이 3분의 1 넓어 한두 크기 커 보인다. 그래서 편집 보기는 GitHub와 Notion처럼 더
    // 작게 써서 본문과 같은 크기로 읽히게 한다.
    static let monoScale = CGFloat(7) / 8
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

    static func preset(_ name: String) -> (accent: PlatformColor, ink: PlatformColor) {
        let a = CourseAccent.presets.first { $0.name == name }?.accent ?? .gray
        return (a.native, a.inkNative)
    }

    static func callout(_ type: String) -> PlatformColor {
        switch type {
        case "definition", "info", "note", "abstract": preset("blue").accent
        case "theorem", "lemma", "corollary", "proposition": preset("violet").accent
        case "example", "counterexample", "tip", "summary", "solution": preset("green").accent
        case "warning", "important", "question": preset("orange").accent
        case "danger": danger
        default: CourseAccent.gray.native
        }
    }

    // 하이라이터의 `tok-*` class(resources/web/native.js)에 따라 색을 정한다.
    static func token(_ classes: String) -> (color: PlatformColor, italic: Bool)? {
        let set = Set(classes.split(separator: " ").map(String.init))
        // 토큰 하나에 class가 여럿 붙으므로(호출한 메서드는 property이면서 function이다) 처음 맞는 것을 쓴다.
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
