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
        // Room first: filling hides a ℝ typed in `\text{…}` inside a command, where `reserve` could no longer see it.
        TeXGaps.fill(Blackboard.reserve(syntax == .asciimath ? NoteScripts.tex(fromAsciiMath: source) : source))
    }

    /// Nil when SwiftMath can't read the TeX; the caller shows the source instead.
    static func picture(_ source: String, syntax: MathSyntax, display: Bool, size: CGFloat, color: PlatformColor, dark: Bool) -> Picture? {
        let resolved = resolve(color, dark: dark)
        let key = "\(syntax.rawValue)|\(display)|\(size)|\(resolved)|\(source)"
        if let hit = cache[key] { return hit }
        if failed.contains(key) { return nil }
        let tex = tex(source, syntax).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tex.isEmpty, let list = typeset(tex, display: display, size: size, color: resolved) else {
            failed.insert(key)
            return nil
        }
        let box = CGSize(width: list.width, height: list.ascent + list.descent)
        var edges = overflow(list, box: box, size: size)
        // Whole points, so the picture isn't stretched into its bounds.
        edges.right += ceil(box.width + edges.left + edges.right) - (box.width + edges.left + edges.right)
        edges.top += ceil(box.height + edges.top + edges.bottom) - (box.height + edges.top + edges.bottom)
        let canvas = CGSize(width: round(box.width + edges.left + edges.right), height: round(box.height + edges.top + edges.bottom))
        guard let image = draw(list, size: canvas, offset: CGPoint(x: edges.left, y: edges.bottom)) else {
            failed.insert(key)
            return nil
        }
        let result = Picture(image: image, size: canvas, descent: list.descent + edges.bottom)
        cache[key] = result
        return result
    }

    /// The typeset formula, laid out by the label with its box's corner at the origin, or nil when SwiftMath can't read the TeX. Drawn here,
    /// not by SwiftMath's picture, which typesets again and would lose the double-struck letters swapped in.
    static func typeset(_ tex: String, display: Bool, size: CGFloat, color: PlatformColor) -> MTMathListDisplay? {
        let label = MTMathUILabel()
        label.labelMode = display ? .display : .text
        label.fontSize = size
        // Setting the color rebuilds every line from SwiftMath's own text, so it goes before the swap.
        label.textColor = color
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
        guard label.error == nil, let list = label.displayList else { return nil }
        // Rebuilding lines walks every glyph, so formulas without the letters skip it.
        if Blackboard.reserved(tex) { Blackboard.restyle(list) }
        return list
    }

    /// Nil for a formula with no area (`\,`), which has nothing to draw into.
    private static func draw(_ list: MTMathListDisplay, size: CGSize, offset: CGPoint) -> PlatformImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(macOS)
        // Drawn once, now, so the cache keeps a bitmap and not SwiftMath's display tree, which a deferred drawing
        // handler would have to hold and touch off the main actor. At the sharpest attached screen's scale but never
        // below Retina's: a cached picture may later show on a Retina screen, and a machine with no display reports 1.
        let scale = max(2, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: offset.x, y: offset.y)
        // SwiftMath colors a stretched delimiter, a fraction's bar and a root with `NSColor.setFill()`, which sets the
        // current graphics context's color, not this one's; with none current they came out black. On the iPad the
        // image renderer makes its context current.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        list.draw(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { NSImage(cgImage: $0, size: size) }
        #else
        return UIGraphicsImageRenderer(size: size).image { renderer in
            renderer.cgContext.translateBy(x: 0, y: size.height)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            renderer.cgContext.translateBy(x: offset.x, y: offset.y)
            list.draw(renderer.cgContext)
        }
        #endif
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
        // The list sits at the box's corner, as it will in the picture after its insets.
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

/// `\mathbb` capitals in the AMS blackboard font that LaTeX and KaTeX use. Latin Modern Math, SwiftMath's font, draws
/// them as thin open outlines (ℝ, 𝔽) that read as another alphabet next to every other place the note is shown.
/// SwiftMath sets one font per line and loads fonts only from its own bundle, so after typesetting each line holding
/// such a letter is rebuilt from its glyphs with the letter in the AMS font. The AMS letters are mostly wider (M by a
/// third), so before typesetting each one is followed by a space of the difference: SwiftMath then places what comes
/// next, scripts included, past the AMS letter, and the rebuilt line is kerned back to the width SwiftMath measured.
@MainActor enum Blackboard {
    private static let ams: CGFont? = Bundle.main.url(forResource: "KaTeX_AMS-Regular.ttf", withExtension: nil)
        .flatMap { CGDataProvider(url: $0 as CFURL) }.flatMap { CGFont($0) }
    nonisolated private static let capitals = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    // Only bodies of plain letters and digits are split; `\mathbb{R^2}` or `\mathbb{R\times S}` split by character
    // would leave `\mathbb{^}` or `\mathbb{\}`, which SwiftMath can't read, so those stay as written.
    private static let mathbb = try! NSRegularExpression(pattern: #"\\mathbb(?![A-Za-z])\s*(?:\{([A-Za-z0-9\s]*)\}|([A-Za-z0-9]))"#)
    // Not the start of a longer command (`\mathbbm`), which SwiftMath doesn't know and shows as source.
    private static let command = try! NSRegularExpression(pattern: #"\\mathbb(?![A-Za-z])"#)

    /// Each `\mathbb` capital as its own command followed by its room, so it can be one letter wide in either font.
    /// All or nothing: a body it can't split (`\mathbb{R^2}`) or a double-struck capital typed as itself (ℝ) would get
    /// the AMS letter with no room after it, so then the formula is left as written and stays Latin Modern.
    static func reserve(_ tex: String) -> String {
        guard ams != nil, tex.contains("\\mathbb"),
              !tex.unicodeScalars.contains(where: { typed.contains($0) }) else { return tex }
        let whole = tex as NSString
        let matches = mathbb.matches(in: tex, range: NSRange(location: 0, length: whole.length))
        guard matches.count == command.numberOfMatches(in: tex, range: NSRange(location: 0, length: whole.length)) else { return tex }
        var out = "", last = 0
        for match in matches {
            out += whole.substring(with: NSRange(location: last, length: match.range.location - last))
            let body = match.range(at: 1).location != NSNotFound ? whole.substring(with: match.range(at: 1)) : whole.substring(with: match.range(at: 2))
            for letter in body where !letter.isWhitespace {
                // Lowercase letters and digits have no AMS form; they stay Latin Modern's.
                guard capitals.contains(letter) else { out += "\\mathbb{\(letter)}"; continue }
                guard let room = room(letter) else { return tex }
                out += "\\mathbb{\(letter)}\\\(room) "
            }
            last = match.range.location + match.range.length
        }
        return out + whole.substring(from: last)
    }

    /// Whether `reserve` made room, so the formula's double-struck capitals are all ones it can swap.
    static func reserved(_ tex: String) -> Bool { tex.contains("\\" + roomPrefix) }

    private static let roomPrefix = "foliobbroom"
    private static let typed = Set(capitals.compactMap(doubleStruck))

    private static var rooms: [Character: String?] = [:]

    /// A registered space command as wide as the AMS letter is wider than Latin Modern's, which may be less than none.
    private static func room(_ letter: Character) -> String? {
        if let name = rooms[letter] { return name }
        var name: String?
        if let ams, let scalar = doubleStruck(letter),
           let space = MTMathAtomFactory.atom(forLatexSymbol: "quad") as? MTMathSpace {
            let size: CGFloat = 1000
            func advance(_ font: CTFont, _ text: String) -> CGFloat? {
                var units = Array(text.utf16), glyphs = [CGGlyph](repeating: 0, count: units.count)
                guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return nil }
                return CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, nil, 1)
            }
            if let wide = advance(CTFontCreateWithGraphicsFont(ams, size, nil, nil), String(letter)),
               let narrow = advance(MathFont.latinModernFont.ctFont(withSize: size), String(scalar)) {
                // A quad, 18mu, is the font size.
                space.space = (wide - narrow) / size * 18
                name = roomPrefix + String(letter).lowercased()
                MTMathAtomFactory.add(latexSymbol: name!, value: space)
            }
        }
        rooms[letter] = .some(name)
        return name
    }
    /// Per font: each glyph's text, read back from the font's character map.
    private static var characters: [String: [CGGlyph: String]] = [:]
    /// Per font: its double-struck capitals' glyphs and the letters they are.
    private static var letters: [String: [CGGlyph: UniChar]] = [:]

    static func restyle(_ display: MTDisplay) {
        if let line = display as? MTCTLineDisplay {
            if let rebuilt = swapped(line.line) { line.line = rebuilt }
            return
        }
        // Fractions, radicals, accents and limits keep their parts in properties SwiftMath doesn't all make public.
        var mirror: Mirror? = Mirror(reflecting: display)
        while let m = mirror {
            for child in m.children {
                if let part = child.value as? MTDisplay { restyle(part) }
                if let parts = child.value as? [MTDisplay] { parts.forEach(restyle) }
            }
            mirror = m.superclassMirror
        }
    }

    /// The line again with its double-struck capitals in the AMS font, or nil when it has none or can't be read back.
    private static func swapped(_ line: CTLine) -> CTLine? {
        guard let ams else { return nil }
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let length = CTLineGetStringRange(line).length
        var units = [UniChar](repeating: 0x20, count: length)
        var spans: [(NSRange, [NSAttributedString.Key: Any])] = []
        var swaps: [(at: Int, length: Int, letter: UniChar, font: CTFont, glyph: CGGlyph)] = []
        for run in runs {
            let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
            guard let value = attributes[NSAttributedString.Key(kCTFontAttributeName as String)] else { return nil }
            let font = value as! CTFont
            let count = CTRunGetGlyphCount(run), range = CTRunGetStringRange(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetStringIndices(run, CFRange(), &indices)
            let text = characterMap(font), doubled = letterMap(font)
            for i in 0..<count {
                let end = i + 1 < count ? indices[i + 1] : range.location + range.length
                // A glyph standing for other than its one character (a ligature, a mark) can't be rebuilt.
                guard let character = text[glyphs[i]], character.utf16.count == end - indices[i], end <= length else { return nil }
                units.replaceSubrange(indices[i]..<end, with: character.utf16)
                if let letter = doubled[glyphs[i]] { swaps.append((indices[i], end - indices[i], letter, font, glyphs[i])) }
            }
            spans.append((NSRange(location: range.location, length: range.length), attributes))
        }
        guard !swaps.isEmpty else { return nil }
        let string = NSMutableAttributedString(string: String(utf16CodeUnits: units, count: length))
        for (range, attributes) in spans { string.setAttributes(attributes, range: range) }
        let kern = NSAttributedString.Key(kCTKernAttributeName as String)
        // From the end, since a letter is shorter than the surrogate pair it replaces.
        for swap in swaps.reversed() {
            let range = NSRange(location: swap.at, length: swap.length)
            var attributes = string.attributes(at: swap.at, effectiveRange: nil)
            let size = CTFontGetSize(swap.font)
            let font = CTFontCreateWithGraphicsFont(ams, size, nil, nil)
            var letter = swap.letter, glyph: CGGlyph = 0, old = swap.glyph
            guard CTFontGetGlyphsForCharacters(font, &letter, &glyph, 1) else { continue }
            let width = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
            let was = CTFontGetAdvancesForGlyphs(swap.font, .horizontal, &old, nil, 1)
            attributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
            attributes[kern] = ((attributes[kern] as? NSNumber)?.doubleValue ?? 0) + was - width
            string.replaceCharacters(in: range, with: NSAttributedString(string: String(utf16CodeUnits: [letter], count: 1), attributes: attributes))
        }
        return CTLineCreateWithAttributedString(string)
    }

    private static func characterMap(_ font: CTFont) -> [CGGlyph: String] {
        let name = CTFontCopyPostScriptName(font) as String
        if let map = characters[name] { return map }
        var map: [CGGlyph: String] = [:]
        let set = CTFontCopyCharacterSet(font)
        // The math alphabets are past the first plane.
        for value in UInt32(0x20)..<0x20000 where CFCharacterSetIsLongCharacterMember(set, value) {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), map[glyphs[0]] == nil { map[glyphs[0]] = String(scalar) }
        }
        characters[name] = map
        return map
    }

    /// Where SwiftMath finds the letter's double-struck form: in Letterlike Symbols for the ones Unicode had first.
    nonisolated private static func doubleStruck(_ letter: Character) -> Unicode.Scalar? {
        let older: [Character: UInt32] = ["C": 0x2102, "H": 0x210D, "N": 0x2115, "P": 0x2119, "Q": 0x211A, "R": 0x211D, "Z": 0x2124]
        guard let offset = capitals.firstIndex(of: letter).map({ capitals.distance(from: capitals.startIndex, to: $0) }) else { return nil }
        return Unicode.Scalar(older[letter] ?? 0x1D538 + UInt32(offset))
    }

    private static func letterMap(_ font: CTFont) -> [CGGlyph: UniChar] {
        let name = CTFontCopyPostScriptName(font) as String
        if let map = letters[name] { return map }
        var map: [CGGlyph: UniChar] = [:]
        for letter in capitals {
            guard let scalar = doubleStruck(letter) else { continue }
            let units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) { map[glyphs[0]] = letter.utf16.first }
        }
        letters[name] = map
        return map
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
