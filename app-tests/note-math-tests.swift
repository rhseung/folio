import AppKit
import FolioDomain
import Foundation
import SwiftMath
import Testing
@testable import Folio

/// Math drawn by SwiftMath for the edit view's bubble (`NoteMath`): the whole formula's ink, commands SwiftMath lacks,
/// double-struck capitals and text inside math.
@MainActor @Suite(.serialized)
struct NoteMathTests {
    @Test func mathKeepsInkThatLeavesItsBox() throws {
        func ink(_ image: NSImage) throws -> CGSize {
            let scale: CGFloat = 2, pad: CGFloat = 40
            let w = Int((image.size.width + 2 * pad) * scale), h = Int((image.size.height + 2 * pad) * scale)
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: CGPoint(x: pad, y: pad), size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            var box = CGRect.null
            for x in 0..<w { for y in 0..<h where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { box = box.union(CGRect(x: x, y: y, width: 1, height: 1)) } }
            return box.size
        }
        for tex in [#"G - T"#, #"\bar S"#, #"\|T\| \ge \|\kappa\|"#, #"f"#] {
            let picture = try #require(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false))
            // SwiftMath's own picture with room on every side: all the ink the formula has.
            let whole = MTMathImage(latex: tex, fontSize: 16, textColor: .black, labelMode: .text)
            whole.contentInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            let reference = try #require(whole.asImage().1)
            let (got, want) = (try ink(picture.image), try ink(reference))
            // A pixel either way is antialiasing: the two are drawn at different fractions of a point.
            #expect(abs(got.width - want.width) <= 1 && abs(got.height - want.height) <= 1, "\(tex): \(got) vs \(want)")
        }
    }

    @Test func everydayCommandsSwiftMathLacksStillDraw() throws {
        for tex in [#"0, \dots, n-1"#, #"i \bmod n"#, #"a \equiv b \pmod{n}"#, #"a \mod n"#, #"\operatorname{rank} A"#,
                    #"p \implies q"#, #"q \impliedby p"#, #"A \subsetneq B"#, #"a \nmid b"#, #"\therefore x"#, #"\blacksquare"#,
                    #"\square"#, #"\varnothing"#, #"\lvert x \rvert"#, #"\iint f"#, #"\dfrac{1}{2}"#, #"\bigl( x \bigr)"#,
                    #"\boxed{x}"#, #"a \xrightarrow{f} b"#, #"\overset{?}{=}"#, #"a \not= b"#, #"a \lt b"#,
                    #"\left\lvert x \right\rvert"#, #"\left\lVert x \right\rVert"#, #"\lVert x \rVert"#] {
            #expect(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false) != nil, "\(tex)")
        }
        #expect(NoteMath.picture(#"\notacommand{x}"#, syntax: .latex, display: false, size: 16, color: .black, dark: false) == nil)
    }

    @Test func doubleStruckCapitalsUseTheAMSFont() throws {
        func fonts(_ display: MTDisplay) -> [String] {
            if let line = display as? MTCTLineDisplay {
                return (CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []).map {
                    let attributes = CTRunGetAttributes($0) as NSDictionary
                    return CTFontCopyPostScriptName(attributes[kCTFontAttributeName] as! CTFont) as String
                }
            }
            var found: [String] = [], mirror: Mirror? = Mirror(reflecting: display)
            while let m = mirror {
                for child in m.children {
                    if let part = child.value as? MTDisplay { found += fonts(part) }
                    if let parts = child.value as? [MTDisplay] { found += parts.flatMap(fonts) }
                }
                mirror = m.superclassMirror
            }
            return found
        }
        for tex in [NoteMath.tex("u in F^2, RR", .asciimath), NoteMath.tex(#"\sqrt{\mathbb{Z}}"#, .latex), NoteMath.tex(#"\frac{\mathbb{Q}}{2}"#, .latex)] {
            let list = try #require(NoteMath.typeset(tex, display: false, size: 16, color: .black), "\(tex)")
            #expect(fonts(list).contains("KaTeX_AMS-Regular"), "\(tex)")
        }
        // Kerned back to Latin Modern's width, so what SwiftMath placed after the letter stays put.
        let swapped = try #require(NoteMath.typeset(NoteMath.tex(#"\mathbb{R}^2"#, .latex), display: false, size: 16, color: .black))
        #expect(fonts(swapped).contains("KaTeX_AMS-Regular"))
        let line = try #require(swapped.subDisplays.first as? MTCTLineDisplay)
        #expect(abs(CTLineGetTypographicBounds(line.line, nil, nil, nil) - line.width) < 0.01)
        // The AMS M is a third wider than Latin Modern's; SwiftMath makes room for it rather than overlapping the next.
        let pair = try #require(NoteMath.picture(#"\mathbb{MM}"#, syntax: .latex, display: false, size: 16, color: .black, dark: false))
        #expect(pair.size.width >= 2 * 0.944 * 16 - 1)
        // With no room after it, an AMS letter would run into what follows, so a formula with a body that can't be
        // split, or a double-struck capital typed as itself, stays as written and all Latin Modern, with no room added.
        for tex in [#"\mathbb{R^2}"#, #"\mathbb{R\times S}"#, #"\mathbb{M} + \mathbb{R^2}"#, #"ℝ + \mathbb{M}"#] {
            #expect(NoteMath.tex(tex, .latex) == tex)
            let list = try #require(NoteMath.typeset(NoteMath.tex(tex, .latex), display: false, size: 16, color: .black), "\(tex)")
            #expect(!fonts(list).contains("KaTeX_AMS-Regular"), "\(tex)")
            #expect(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false) != nil, "\(tex)")
        }
        // A ℝ typed in text is hidden in a command once text is filled, so it must be seen before.
        let typed = try #require(NoteMath.typeset(NoteMath.tex(#"\text{ℝ} = \mathbb{R}"#, .latex), display: false, size: 16, color: .black))
        #expect(!fonts(typed).contains("KaTeX_AMS-Regular"))
        // A longer command that starts the same is left alone, so it still shows as source rather than as 𝕞1.
        #expect(NoteMath.tex(#"\mathbbm{1}"#, .latex) == #"\mathbbm{1}"#)
        #expect(NoteMath.picture(#"\mathbbm{1}"#, syntax: .latex, display: false, size: 16, color: .black, dark: false) == nil)
    }

    @Test func textInMathReadsAsText() throws {
        func width(_ tex: String) throws -> CGFloat {
            try #require(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false), "\(tex)").size.width
        }
        // Math puts room around a minus and a ratio colon; text doesn't.
        #expect(try width(#"\text{a-b}"#) < width(#"\mathrm{a}-\mathrm{b}"#))
        #expect(try width(#"\text{a:b}"#) < width(#"\mathrm{a}:\mathrm{b}"#))
        // Past ASCII SwiftMath dropped the character.
        #expect(try width(#"\text{a–b}"#) > width(#"\text{ab}"#))
        #expect(try width(#"\text{a--b}"#) == width(#"\text{a–b}"#))
        #expect(try width(#"x\text{양이온}"#) > width("x") + 24)
        #expect(try width(#"\text{König–Egerváry: } \alpha'(G) = \beta(G)"#) > 0)
        // SwiftMath dropped `$ % # ~` and read `&` as a table column.
        #expect(try width(#"\text{5% 이내}"#) > width(#"\text{5 이내}"#))
        #expect(try width(#"\text{#3}"#) > width(#"\text{3}"#))
        #expect(try width(#"\text{A&B}"#) == width(#"\text{A\&B}"#))
        #expect(try width(#"\text{a~b}"#) == width(#"\text{a b}"#))
        // Only `\text` kept its spaces.
        #expect(try width(#"\textbf{a b}"#) > width(#"\textbf{ab}"#))
        #expect(try width(#"\textit{강조}"#) > 24)
    }
}
