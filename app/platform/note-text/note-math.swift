import FolioDomain
import JavaScriptCore
import SwiftMath
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// AsciiMath to TeX and code colors come from npm packages (resources/web/native.js), run in JavaScriptCore with no
/// page: there is no maintained Swift port of asciimath2tex, and the code languages stay the ones notes always had.
@MainActor enum NoteScripts {
    private static let helpers: JSValue? = {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(NoteStyle.resource("native.js"))
        return context.objectForKeyedSubscript("folioNative")
    }()
    private static var texCache: [String: String] = [:]

    static func tex(fromAsciiMath source: String) -> String {
        if let tex = texCache[source] { return tex }
        let tex = helpers?.objectForKeyedSubscript("toTeX").call(withArguments: [source])?.toString() ?? source
        texCache[source] = tex
        return tex
    }

    /// Token spans in UTF-16 offsets of `code`, with the highlighter's classes.
    static func highlight(_ code: String, language: String) -> [(range: NSRange, classes: String)] {
        guard let flat = helpers?.objectForKeyedSubscript("highlight").call(withArguments: [code, language])?.toArray() else { return [] }
        return stride(from: 0, to: flat.count - 2, by: 3).compactMap { i in
            guard let from = flat[i] as? Int, let to = flat[i + 1] as? Int, let cls = flat[i + 2] as? String else { return nil }
            return (NSRange(location: from, length: to - from), cls)
        }
    }
}

/// Math typeset by SwiftMath into a picture, kept by its source, size, color and appearance.
@MainActor enum NoteMath {
    struct Picture {
        let image: PlatformImage
        let size: CGSize
        /// Below the baseline, so inline math sits on the line with the text.
        let descent: CGFloat
    }

    private static var cache: [String: Picture] = [:]
    private static var failed: Set<String> = []

    static func tex(_ source: String, _ syntax: MathSyntax) -> String {
        syntax == .asciimath ? NoteScripts.tex(fromAsciiMath: source) : source
    }

    /// Nil when SwiftMath can't read the TeX; the caller shows the source instead.
    static func picture(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, color: PlatformColor, dark: Bool) -> Picture? {
        let resolved = resolve(color, dark: dark)
        let key = "\(syntax.rawValue)|\(display)|\(size)|\(resolved)|\(source)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        let tex = tex(source, syntax).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = MTMathUILabel()
        label.labelMode = display ? .display : .text
        label.fontSize = size
        label.textColor = resolved
        label.latex = tex
        #if os(macOS)
        let fitted = label.fittingSize
        #else
        let fitted = label.intrinsicContentSize
        #endif
        // The label only keeps its typeset list after laying out.
        label.frame = CGRect(origin: .zero, size: fitted)
        #if os(macOS)
        label.layout()
        #else
        label.layoutSubviews()
        #endif
        let image = MTMathImage(latex: tex, fontSize: size, textColor: resolved, labelMode: display ? .display : .text)
        guard label.error == nil, !tex.isEmpty, let list = label.displayList, case (nil, let picture?) = image.asImage() else {
            failed.insert(key)
            return nil
        }
        let result = Picture(image: picture, size: CGSize(width: ceil(fitted.width), height: ceil(list.ascent + list.descent)), descent: list.descent)
        cache[key] = result
        return result
    }

    /// The color as it looks in the given appearance: the picture is drawn once, so a dynamic color can't follow later.
    static func resolve(_ color: PlatformColor, dark: Bool) -> PlatformColor {
        #if os(macOS)
        var out = color
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance { out = color.usingColorSpace(.sRGB) ?? color }
        return out
        #else
        return color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        #endif
    }
}
