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
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.orderBack(nil)
        return window
    }()

    /// The picture once drawn; nil when it fails or doesn't come in time.
    func picture(_ source: String, _ syntax: MathSyntax = .latex, display: Bool = false, dark: Bool = false,
                 by math: NoteMath = .shared) async -> NoteMath.Picture? {
        math.host(in: Self.window.contentView!)
        var done = false
        if let hit = math.picture(source, syntax: syntax, display: display, size: 16, dark: dark, ready: { done = true }) { return hit }
        let clock = ContinuousClock(), until = clock.now + .seconds(20)
        while !done, clock.now < until {
            // Another test's editor may have taken the page into its window.
            math.host(in: Self.window.contentView!)
            try? await Task.sleep(for: .milliseconds(20))
        }
        return math.picture(source, syntax: syntax, display: display, size: 16, dark: dark)
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

    /// The picture holds all the ink: none touches its edge, so an italic overhang or a tall accent isn't cut.
    @Test func picturesKeepTheirInk() async throws {
        for tex in [#"G - T"#, #"\bar S"#, #"\int_0^1 f"#, #"\hat{A}^{T}"#, #"\sqrt{\frac{a}{b}}"#] {
            let picture = try #require(await picture(tex), "\(tex)")
            let pixels = try Pixels(picture.image)
            #expect(pixels.inked > 0, "\(tex)")
            #expect(pixels.edgeInk == 0, "\(tex): \(pixels.edgeInk) inked pixels on the edge")
        }
    }

    /// Drawn in the note's text color for the appearance asked for, not the page's.
    @Test func inkFollowsTheAppearance() async throws {
        for dark in [false, true] {
            let picture = try #require(await picture(#"\left( \frac{a}{b} \right) + \sqrt{x}"#, dark: dark))
            let pixels = try Pixels(picture.image)
            #expect(pixels.inked > 0)
            if dark { #expect(pixels.darkInk == 0, "\(pixels.darkInk) dark of \(pixels.inked)") } else { #expect(pixels.lightInk == 0, "\(pixels.lightInk) light of \(pixels.inked)") }
        }
    }

    private struct Pixels {
        var inked = 0, edgeInk = 0, darkInk = 0, lightInk = 0

        init(_ image: NSImage) throws {
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let (w, h) = (cg.width, cg.height)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let context = try #require(CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    guard bytes[i + 3] > 128 else { continue }
                    inked += 1
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1 { edgeInk += 1 }
                    // Premultiplied: a light pixel's brightest channel is close to its alpha.
                    let bright = Double(max(bytes[i], bytes[i + 1], bytes[i + 2])) / Double(bytes[i + 3])
                    if bright < 0.5 { darkInk += 1 } else { lightInk += 1 }
                }
            }
        }
    }
}
