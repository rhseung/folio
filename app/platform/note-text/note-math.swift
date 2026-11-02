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
        guard label.error == nil, !tex.isEmpty, let list = label.displayList else {
            failed.insert(key)
            return nil
        }
        let box = CGSize(width: list.width, height: list.ascent + list.descent)
        var edges = overflow(list, box: box, size: size)
        // Whole points, so the picture isn't stretched into its bounds.
        edges.right += ceil(box.width + edges.left + edges.right) - (box.width + edges.left + edges.right)
        edges.top += ceil(box.height + edges.top + edges.bottom) - (box.height + edges.top + edges.bottom)
        let image = MTMathImage(latex: tex, fontSize: size, textColor: resolved, labelMode: display ? .display : .text)
        image.contentInsets = edges
        guard case (nil, let picture?) = image.asImage() else {
            failed.insert(key)
            return nil
        }
        let result = Picture(image: picture, size: CGSize(width: round(box.width + edges.left + edges.right), height: round(box.height + edges.top + edges.bottom)),
                             descent: list.descent + edges.bottom)
        cache[key] = result
        return result
    }

    /// How far the ink reaches past the typeset box. SwiftMath sizes its picture to the box, which leaves out an italic
    /// letter's overhang (the T in `G - T`) and an accent over a capital (`\bar S`), so those were cut off.
    private static func overflow(_ list: MTMathListDisplay, box: CGSize, size: CGFloat) -> MTEdgeInsets {
        let scale: CGFloat = 2, pad = size
        let width = Int(((box.width + 2 * pad) * scale).rounded(.up)), height = Int(((box.height + 2 * pad) * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return MTEdgeInsets() }
        context.scaleBy(x: scale, y: scale)
        // The label laid the list out at the box's corner, as the picture will with its insets.
        context.translateBy(x: pad, y: pad)
        list.draw(context)
        let alpha = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for x in 0..<width where alpha[(row * width + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return MTEdgeInsets() }
        // Rows run from the top, the box's y from the bottom.
        let ink = CGRect(x: CGFloat(minX) / scale - pad, y: CGFloat(height - 1 - maxRow) / scale - pad,
                         width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxRow - minRow + 1) / scale)
        return MTEdgeInsets(top: ceil(max(0, ink.maxY - box.height)), left: ceil(max(0, -ink.minX)),
                            bottom: ceil(max(0, -ink.minY)), right: ceil(max(0, ink.maxX - box.width)))
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
