import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

/// Math for the edit view's bubble and completion menu (`NoteMath`), drawn by the preview's KaTeX in a hidden page:
/// every command the menu offers draws, the formulas that came out otherwise than in the preview, the whole ink, the
/// appearance's color, and how long a picture takes.
@MainActor @Suite(.serialized)
struct NoteMathTests {
    /// Carries the page as the edit view does, in a window nobody sees.
    static let window: NSWindow = {
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 300), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.orderBack(nil)
        return window
    }()

    /// The picture once drawn; nil when it fails or doesn't come in time. Trimmed to its ink, as the bubble's is,
    /// unless asked otherwise.
    func picture(
        _ source: String, _ syntax: MathSyntax = .latex, display: Bool = false, dark: Bool = false, trim: Bool = true,
        by math: NoteMath = .shared
    ) async -> NoteMath.Picture? {
        math.host(in: Self.window.contentView!)
        var done = false
        if let hit = math.picture(source, syntax: syntax, display: display, size: 16, dark: dark, trim: trim, ready: { done = true }) {
            return hit
        }
        let clock = ContinuousClock(), until = clock.now + .seconds(20)
        while !done, clock.now < until {
            // Another test's editor may have taken the page into its window.
            math.host(in: Self.window.contentView!)
            try? await Task.sleep(for: .milliseconds(20))
        }
        return math.picture(source, syntax: syntax, display: display, size: 16, dark: dark, trim: trim)
    }

    /// The first picture waits for a web process and the page; later ones only for KaTeX and the snapshot. A new
    /// renderer, as the app's is when its first editor opens, so the first is measured from cold. Printed for the PR.
    @Test func picturesComeQuickly() async throws {
        let math = NoteMath(), clock = ContinuousClock()
        var start = clock.now
        #expect(await picture(#"\sum_{k=1}^{n} k = \frac{n(n+1)}{2}"#, by: math) != nil)
        let cold = clock.now - start
        var warm: [Duration] = []
        for tex in [#"\int_0^1 x^2 \, dx = \frac{1}{3}"#, #"\underbrace{a + b}_{n}"#, #"\mathbb{R}^n \to \mathbb{R}"#, "x^2"] {
            start = clock.now
            #expect(await picture(tex, by: math) != nil)
            warm.append(clock.now - start)
        }
        print("NoteMath timing: first picture \(cold) (page made to picture \(math.firstPicture.map { "\($0)" } ?? "-")), then \(warm)")
        #expect(warm.allSatisfy { $0 < .seconds(1) }, "\(warm)")
    }

    /// Whatever the menu offers draws in the bubble too, as it does in the preview: with SwiftMath a fifth didn't.
    @Test func everyOfferedCommandDraws() async throws {
        for command in TeXCommands.all where !["left", "right"].contains(command.name) {
            #expect(await picture(command.sample) != nil, "\(command.sample)")
        }
        #expect(await picture(#"\left( \frac{a}{b} \right)"#) != nil)
        for environment in TeXCommands.environments {
            let body = environment.hasPrefix("equation") ? "a = b" : #"a & b \\ c & d"#
            let tex = "\\begin{\(environment)} \(body) \\end{\(environment)}"
            #expect(await picture(tex, display: true) != nil, "\(tex)")
        }
        #expect(await picture(#"\notacommand{x}"#) == nil)
    }

    /// Formulas the bubble drew otherwise than the preview, or not at all (#389).
    @Test func drawsWhatThePreviewDraws() async throws {
        let cases: [(String, MathSyntax, Bool)] = [
            ("ubrace(abs(R cap {a_1,...,a_m}))_(m - absI)", .asciimath, false),
            (##"min{|F|: G - F " separates " x, y} = max{"# edge-disjoint " x,y- "paths"}"##, .asciimath, false),
            ("|(bigcup_(i in I) A_i) cap (bigcup_(i in J) B_i)| >= |I| + |J| - m", .asciimath, true),
            (#"\overbrace{a + b}^{n} \cancel{x} \boxed{y} \boldsymbol{v} \underset{n}{\lim}"#, .latex, false),
            (#"\text{과제 #3, 5% 이내, A & B}"#, .latex, false),
        ]
        for (source, syntax, display) in cases {
            #expect(await picture(source, syntax, display: display) != nil, "\(source)")
        }
        // The brace takes room under the formula: the picture is taller than the formula without it.
        let braced = try #require(await picture(#"\underbrace{a + b}_{n}"#))
        let plain = try #require(await picture(#"{a + b}_{n}"#))
        #expect(braced.size.height > plain.size.height + 4)
        // The brace is a 400em picture its box clips; measured whole, the picture ran the page's width.
        #expect(braced.size.width < plain.size.width + 16, "\(braced.size) vs \(plain.size)")
    }

    /// The shapes a formula takes, in TeX and in AsciiMath: from one letter to a line wider than the column, with
    /// what reaches above and below a line (limits, fractions, roots, braces, big delimiters, rows). The last three are
    /// the ones the bubble drew with room the formula didn't need: a line box over the ink, and a display formula as
    /// wide as the column with the formula at its left.
    static let shapes: [(name: String, tex: String, ascii: String)] = [
        ("한 글자", "x", "x"),
        ("숫자", "1", "1"),
        ("위첨자", "x^2", "x^2"),
        ("아래첨자", "a_i", "a_i"),
        ("합", #"\sum_{i=1}^{n} i"#, "sum_(i=1)^n i"),
        ("적분", #"\int_0^1 f(x)\,dx"#, "int_0^1 f(x) dx"),
        ("극한", #"\lim_{x\to0} \frac{\sin x}{x}"#, "lim_(x->0) (sin x)/x"),
        ("겹친 분수", #"\frac{a}{\frac{b}{c}}"#, "a/(b/c)"),
        ("근호", #"\sqrt{x} + \sqrt[n]{y}"#, "sqrt(x) + root(n)(y)"),
        ("행렬", #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#, "((a, b), (c, d))"),
        ("경우", #"\begin{cases} x & x > 0 \\ -x & \text{otherwise} \end{cases}"#, #"{(x, x > 0), (-x, "otherwise"):}"#),
        ("정렬", #"\begin{aligned} a &= b + c \\ &= d \end{aligned}"#, "{:(a, =, b + c), (, =, d):}"),
        ("중괄호", #"\underbrace{a + b}_{n} \overbrace{c}^{m}"#, "ubrace(a + b)_n obrace(c)^m"),
        ("윗줄", #"\overline{AB}"#, "bar(AB)"),
        ("큰 괄호", #"\left(\frac{a}{b}\right)"#, "(a/b)"),
        ("화살표", #"A \xrightarrow{f \circ g} B \to C"#, "A stackrel(f @ g)(->) B -> C"),
        ("한글", #"\text{확률 } P(A) = \frac{1}{2}"#, #""확률 " P(A) = 1/2"#),
        (
            "긴 줄", (1...24).map { "a_{\($0)} x^{\($0)}" }.joined(separator: " + "),
            (1...24).map { "a_(\($0)) x^(\($0))" }.joined(separator: " + ")
        ),
        (
            "합집합 블록", #"\left|\left(\bigcup_{i \in I} A_i\right) \cap \left(\bigcup_{i \in J} B_i\right)\right| \geq |I| + |J| - m"#,
            "abs((bigcup_(i in I) A_i) cap (bigcup_(i in J) B_i)) >= absI + absJ - m"
        ),
        ("합집합", #"\left|\bigcup_{i \in I} A_i\right| \geq |I|"#, "abs(bigcup_(iinI)A_i) >= abs(I)"),
        ("목록", "s_1,s_2,s_3,s_4,s_5", "s_1,s_2,s_3,s_4,s_5"),
    ]

    /// Every shape in both syntaxes, inline and as a block.
    static var hugged: [(String, MathSyntax, Bool)] {
        shapes.flatMap { shape -> [(String, MathSyntax, Bool)] in
            [(shape.tex, .latex, false), (shape.tex, .latex, true), (shape.ascii, .asciimath, false), (shape.ascii, .asciimath, true)]
        }
    }

    /// The picture is the formula's ink and nothing around it, so the bubble's even padding is all the room there is:
    /// no side has more than the pixel the picture's whole points round to.
    @Test func picturesAreTheirInk() async throws {
        for (source, syntax, display) in Self.hugged {
            for dark in [false, true] {
                let picture = try #require(await picture(source, syntax, display: display, dark: dark), "\(source)")
                let pixels = try Pixels(picture.image)
                let ink = try #require(pixels.ink, "\(source)")
                let scale = CGFloat(pixels.width) / picture.size.width
                #expect(abs(CGFloat(pixels.height) / picture.size.height - scale) < 0.01, "\(source): stretched")
                let margins = [ink.minX, ink.minY, pixels.width - 1 - ink.maxX, pixels.height - 1 - ink.maxY]
                #expect(
                    margins.allSatisfy { CGFloat($0) < scale }, "\(source) dark \(dark): margins \(margins) at \(scale)x, \(picture.size)")
            }
        }
        // Nothing to draw, or what KaTeX can't read: no picture, and no bubble.
        #expect(NoteMath.shared.picture("  ", syntax: .latex, display: false, size: 16, dark: false) == nil)
        #expect(await picture(#"\frac{a}"#) == nil)
        #expect(await picture(#"\frac{a}"#, display: true) == nil)
    }

    /// Cut to its ink, the picture still holds all of it: drawn with three times the room around KaTeX's boxes, a
    /// limit, a brace or a slanted integral comes out no bigger.
    @Test func picturesKeepTheirInk() async throws {
        let roomy = NoteMath(room: 3)
        let tall = [#"G - T"#, #"\bar S"#, #"\int_0^1 f"#, #"\hat{A}^{T}"#, #"\sqrt{\frac{a}{b}}"#, #"\underbrace{a + b}_{n}"#]
        for tex in tall {
            let tight = try #require(await picture(tex), "\(tex)")
            let wide = try #require(await picture(tex, by: roomy), "\(tex)")
            #expect(try Pixels(tight.image).inked > 0, "\(tex)")
            #expect(tight.size == wide.size, "\(tex): \(tight.size) vs \(wide.size)")
        }
        for (source, syntax, display) in Self.hugged {
            let tight = try #require(await picture(source, syntax, display: display), "\(source)")
            let wide = try #require(await picture(source, syntax, display: display, by: roomy), "\(source)")
            #expect(tight.size == wide.size, "\(source): \(tight.size) vs \(wide.size)")
        }
    }

    /// Untrimmed, as the palette and the completion menu ask, a picture keeps KaTeX's line box, so a symbol centered
    /// in its cell still sits where it does on the line: low dots under centered ones, a period under a centered dot.
    @Test func untrimmedPicturesKeepTheirLine() async throws {
        for (low, centered) in [(#"\ldots"#, #"\cdots"#), (".", #"\cdot"#)] {
            func middle(_ tex: String) async throws -> CGFloat {
                let picture = try #require(await picture(tex, trim: false), "\(tex)")
                let pixels = try Pixels(picture.image)
                let ink = try #require(pixels.ink, "\(tex)")
                return CGFloat(ink.minY + ink.maxY) / 2 / CGFloat(pixels.height)
            }
            let l = try await middle(low)
            let c = try await middle(centered)
            // Trimmed, both are at the middle; untrimmed, a tenth of the height apart, give or take a runner's fonts.
            #expect(l > c + 0.05, "\(low) at \(l), \(centered) at \(c) of the picture's height")
        }
    }

    /// The completion menu and the palette show a formula as big as on the note's line and in its own shape: framed to
    /// a row's height but its own width, every snippet's preview came out squashed.
    @Test func previewsKeepTheirSizeAndShape() async throws {
        for tex in [#"\frac{a}{b}"#, "x^{2}", #"\sqrt{a}"#, #"\sum_{a}^{b}"#, #"\lim_{a \to b}"#] {
            let picture = try #require(await picture(tex, trim: false), "\(tex)")
            #expect(picture.fitted(CompletionMenuView.previewSlot) == picture.size, "\(tex): \(picture.size)")
            #expect(picture.fitted(MathPaletteCell.glyphSlot) == picture.size, "\(tex): \(picture.size)")
        }
        let slot = CompletionMenuView.previewSlot
        for size in [CGSize(width: 40, height: 120), CGSize(width: 300, height: 30)] {
            let fitted = NoteMath.Picture(image: NSImage(), size: size).fitted(slot)
            #expect(abs(fitted.width / fitted.height - size.width / size.height) < 0.001, "\(size) to \(fitted)")
            #expect(fitted.width <= slot.width && fitted.height <= slot.height, "\(size) to \(fitted)")
        }
    }

    /// A big delimiter is drawn from a font of its own (KaTeX_Size1 to 4). The first formula that needed one came out
    /// with it blank now and then, and the picture was kept: `document.fonts.ready` had settled while the font still
    /// loaded. In a new renderer, first thing or after formulas that need none, the picture has the ink the same
    /// formula has drawn again (untrimmed, so it isn't the kept picture).
    @Test func bigDelimitersDrawTheFirstTime() async throws {
        let formulas: [(String, MathSyntax)] = [
            (
                "det(B - tI) = det(Q^-1AQ - tI) = det(Q^-1(A-tI)Q) =\ndet(Q^-1)det(A - tI)det(Q) = 1/(det(Q)) det(A - tI) det(Q) =\ndet(A - tI)",
                .asciimath
            ),
            (#"\det\left(Q^{-1}\right)"#, .latex),
            (#"\left(\frac{\frac{a}{b}}{\frac{c}{d}}\right) + \left[\sum_{i=1}^{n} x_i\right]"#, .latex),
        ]
        let long = try #require(Self.shapes.first { $0.name == "긴 줄" })
        for (source, syntax) in formulas {
            for after in [[], [(long.tex, MathSyntax.latex, false), (long.ascii, .asciimath, true)]] {
                let math = NoteMath()
                for (other, otherSyntax, dark) in after {
                    #expect(await picture(other, otherSyntax, display: true, dark: dark, by: math) != nil)
                }
                let first = try #require(await picture(source, syntax, display: true, by: math), "\(source)")
                let again = try #require(await picture(source, syntax, display: true, trim: false, by: math), "\(source)")
                let (a, b) = (try Pixels(first.image).inked, try Pixels(again.image).inked)
                #expect(a == b, "\(source), \(after.isEmpty ? "first" : "after others"): \(a) inked pixels, \(b) drawn again")
            }
        }
    }

    /// Drawn in the note's text color for the appearance asked for, not the page's.
    @Test func inkFollowsTheAppearance() async throws {
        for dark in [false, true] {
            let picture = try #require(await picture(#"\left( \frac{a}{b} \right) + \sqrt{x}"#, dark: dark))
            let pixels = try Pixels(picture.image)
            #expect(pixels.inked > 0)
            if dark {
                #expect(pixels.darkInk == 0, "\(pixels.darkInk) dark of \(pixels.inked)")
            } else {
                #expect(pixels.lightInk == 0, "\(pixels.lightInk) light of \(pixels.inked)")
            }
        }
    }

    private struct Pixels {
        var inked = 0, darkInk = 0, lightInk = 0
        var width = 0, height = 0
        /// Every pixel with any ink, its edge included, in pixels from the top left.
        var ink: (minX: Int, minY: Int, maxX: Int, maxY: Int)?

        init(_ image: NSImage) throws {
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let (w, h) = (cg.width, cg.height)
            (width, height) = (w, h)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let context = try #require(
                CGContext(
                    data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    if bytes[i + 3] > 0 {
                        ink = ink.map { (min($0.minX, x), min($0.minY, y), max($0.maxX, x), max($0.maxY, y)) } ?? (x, y, x, y)
                    }
                    guard bytes[i + 3] > 128 else { continue }
                    inked += 1
                    // Premultiplied: a light pixel's brightest channel is close to its alpha.
                    let bright = Double(max(bytes[i], bytes[i + 1], bytes[i + 2])) / Double(bytes[i + 3])
                    if bright < 0.5 { darkInk += 1 } else { lightInk += 1 }
                }
            }
        }
    }
}
