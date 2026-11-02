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
        TeXGaps.fill(syntax == .asciimath ? NoteScripts.tex(fromAsciiMath: source) : source)
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

/// Everyday LaTeX that SwiftMath leaves out. One unknown command made the whole formula fall back to its source, and
/// notes use these often (`\dots`, `\implies`, `\operatorname`). Symbols go into SwiftMath's own table, copied from a
/// symbol of the same kind so they space as relations or operators should; commands that need upright letters or
/// arguments are spelled with ones it has. The rest stay unknown and still show their source.
@MainActor enum TeXGaps {
    /// Name, the symbol to copy for its kind, and the glyph if it differs.
    private static let symbols: [(String, String, String?)] = [
        ("dots", "ldots", nil), ("dotsc", "ldots", nil), ("dotsb", "cdots", nil),
        ("implies", "Longrightarrow", nil), ("impliedby", "Longleftarrow", nil),
        ("subsetneq", "subset", "\u{228A}"), ("supsetneq", "supset", "\u{228B}"), ("nmid", "mid", "\u{2224}"),
        ("lt", "neq", "<"), ("gt", "neq", ">"), ("lesssim", "neq", "\u{2272}"), ("gtrsim", "neq", "\u{2273}"),
        ("rightleftharpoons", "neq", "\u{21CC}"), ("therefore", "neq", "\u{2234}"), ("because", "neq", "\u{2235}"),
        // SwiftMath's `\square` is its input placeholder, drawn in the placeholder color, not the end-of-proof box.
        ("square", "triangle", "\u{25A1}"), ("Box", "triangle", "\u{25A1}"), ("blacksquare", "triangle", "\u{25A0}"),
        ("varnothing", "emptyset", nil),
        ("iint", "int", "\u{222C}"), ("iiint", "int", "\u{222D}"),
    ]

    private static let rewrites: [(NSRegularExpression, String)] = [
        (#"\\operatorname\*?\s*\{([^{}]*)\}"#, #"\\mathrm{$1}\\,"#),
        (#"\\pmod\s*\{([^{}]*)\}"#, #"\\quad(\\mathrm{mod}\\,\\,$1)"#),
        (#"\\pmod\s*([A-Za-z0-9])"#, #"\\quad(\\mathrm{mod}\\,\\,$1)"#),
        (#"\\bmod(?![A-Za-z])"#, #"\\>\\mathrm{mod}\\>"#),
        (#"\\mod(?![A-Za-z])"#, #"\\quad\\mathrm{mod}\\,\\,"#),
        (#"\\[dt]frac(?![A-Za-z])"#, #"\\frac"#),
        (#"\\not\s*="#, #"\\neq"#),
        (#"\\not\s*\\in(?![A-Za-z])"#, #"\\notin"#),
        // Spelled, not added as symbols: after `\left` and `\right` SwiftMath looks only in its fixed delimiter table.
        (#"\\[lr]vert(?![A-Za-z])"#, #"\\vert"#),
        (#"\\[lr]Vert(?![A-Za-z])"#, #"\\Vert"#),
        // Close enough to read: the label over the arrow or symbol sits as its superscript.
        (#"\\xrightarrow\s*\{([^{}]*)\}"#, #"\\longrightarrow^{$1}"#),
        (#"\\xleftarrow\s*\{([^{}]*)\}"#, #"\\longleftarrow^{$1}"#),
        (#"\\overset\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#, #"{$2}^{$1}"#),
        // Sizes and decorations SwiftMath can't draw: the content stays, as a group.
        (#"\\(?:big|Big|bigg|Bigg)[lrm]?(?![A-Za-z])"#, ""),
        (#"\\(?:boxed|cancel|underbrace|overbrace)(?![A-Za-z])"#, ""),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let registered: Void = {
        for (name, kind, glyph) in symbols {
            guard let atom = MTMathAtomFactory.atom(forLatexSymbol: kind) else { continue }
            if let glyph { atom.nucleus = glyph }
            MTMathAtomFactory.add(latexSymbol: name, value: atom)
        }
    }()

    static func fill(_ tex: String) -> String {
        _ = registered
        guard tex.contains("\\") else { return tex }
        return rewrites.reduce(text(tex)) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
        }
    }

    private static let textCommand = try! NSRegularExpression(pattern: #"\\(text|textrm|textbf|textit|texttt|textsf|mbox)\s*\{([^{}]*)\}"#)
    private static var glyphs: Set<String> = []

    /// SwiftMath reads `\text{…}` and its styled kin as math in that font, one character at a time: `-` became a
    /// spaced minus (`1 − factor`), `:` a ratio with relation spacing, `$ % # ~` and anything past ASCII (`–`, Hangul)
    /// were dropped without a word, and `&` split the formula into table columns. Only `\text` kept its spaces. So
    /// each such character becomes an ordinary symbol of itself, which SwiftMath sets in a CoreText line that falls
    /// back to a system font for glyphs the math font lacks, and spaces are spelled `\ `. `--` and `---` are dashes,
    /// as in LaTeX text.
    private static func text(_ tex: String) -> String {
        let whole = tex as NSString
        var out = "", last = 0
        for match in textCommand.matches(in: tex, range: NSRange(location: 0, length: whole.length)) {
            out += whole.substring(with: NSRange(location: last, length: match.range.location - last))
            let command = whole.substring(with: match.range(at: 1))
            out += "\\" + (command == "mbox" ? "text" : command) + "{" + plain(whole.substring(with: match.range(at: 2))) + "}"
            last = match.range.location + match.range.length
        }
        return out + whole.substring(from: last)
    }

    private static func plain(_ body: String) -> String {
        let body = body.replacingOccurrences(of: "---", with: "\u{2014}").replacingOccurrences(of: "--", with: "\u{2013}")
        var out = "", i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            if c == "\\" {
                // A command or escaped character inside the text stays as written.
                var j = body.index(after: i)
                if j < body.endIndex, body[j].isASCII, body[j].isLetter {
                    while j < body.endIndex, body[j].isASCII, body[j].isLetter { j = body.index(after: j) }
                } else if j < body.endIndex {
                    j = body.index(after: j)
                }
                // SwiftMath has no `\&` command, though it has the other escaped specials.
                out += body[i..<j] == "\\&" ? "{\\" + symbol("&") + "}" : String(body[i..<j])
                i = j
                continue
            }
            if c == " " || c == "~" {
                out += "\\ "
            } else if c.isASCII && (c.isLetter || c.isNumber || c == ".") {
                // SwiftMath already sets these as text does.
                out.append(c)
            } else if c == "^" || c == "_" {
                // Scripts in text are an error in LaTeX, so a note that has them means them as scripts.
                out.append(c)
            } else {
                out += "{\\" + symbol(c == "'" ? "\u{2019}" : c) + "}"
            }
            i = body.index(after: i)
        }
        return out
    }

    /// A command for the character, named in letters only since SwiftMath reads a command's name up to the first
    /// non-letter. Registered the first time it's needed.
    private static func symbol(_ c: Character) -> String {
        let digits = Array("abcdefghijklmnop")
        let name = "foliotext" + c.unicodeScalars.map { String(String($0.value, radix: 16).map { digits[Int(String($0), radix: 16)!] }) }.joined(separator: "z")
        if !glyphs.contains(name), let atom = MTMathAtomFactory.atom(forLatexSymbol: "vert") {
            atom.nucleus = String(c)
            MTMathAtomFactory.add(latexSymbol: name, value: atom)
            glyphs.insert(name)
        }
        return name
    }
}
