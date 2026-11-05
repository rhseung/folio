import AppKit
import FolioDomain
import Testing
@testable import Folio

/// Random typing in the write view. After every key, what's shown must be what styling the same text from scratch gives,
/// so no edit path (Enter's list rules, Tab, composing Hangul, deleting) can leave stale or default attributes behind.
@MainActor @Suite(.serialized)
struct NoteTypingTests {
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let starts = ["", "- 하나", "## 제목\n본문", "> 인용", "1. 첫째\n2. 둘째", "본문 **굵게** 끝"]
    static let pieces = ["가", "나", "a", " ", "- ", "# ", "## ", "**", "`", "> ", "1. ", "[ ] ", "-", "=", "$"]

    /// Per character: the font, color and line box it's drawn with. Font names differ where Hangul falls back to
    /// another font, and each accent color is a new dynamic color, so both are compared by what's drawn.
    static func look(_ original: NSAttributedString) -> [String] {
        let text = NSMutableAttributedString(attributedString: original)
        text.fixAttributes(in: NSRange(location: 0, length: text.length))
        var out: [String] = []
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            out = (0..<text.length).map { i in
                let a = text.attributes(at: i, effectiveRange: nil)
                let font = a[.font] as? NSFont
                let traits = font?.fontDescriptor.symbolicTraits ?? []
                let color = (a[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)
                let style = a[.paragraphStyle] as? NSParagraphStyle
                return "\(font?.pointSize ?? 0) b\(traits.contains(.bold)) m\(traits.contains(.monoSpace)) i\(traits.contains(.italic)) "
                    + "\(color.map { String(format: "%.3f %.3f %.3f %.3f", $0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) } ?? "-") "
                    + "\(style?.minimumLineHeight ?? -1) \(style?.maximumLineHeight ?? -1) \(a[.noteCaret] as? CGFloat ?? -1)"
            }
        }
        return out
    }

    @Test(arguments: 0..<24) func whatIsShownIsTheTextStyledFresh(seed: Int) throws {
        var random = SplitMix(state: UInt64(seed))
        let start = Self.starts[seed % Self.starts.count]
        let (view, _) = NoteSourceTests.typing(start)
        let styler = SourceStyler(accent: CourseAccent.presets[0].accent, syntax: .latex, baseURL: NoteRender.fixtures, dark: false)
        var keys: [String] = []
        for _ in 0..<60 {
            let roll = Int.random(in: 0..<10, using: &random)
            switch roll {
            case 0: view.insertNewline(nil); keys.append("⏎")
            case 1: view.insertTab(nil); keys.append("⇥")
            case 2: view.insertBacktab(nil); keys.append("⇤")
            case 3: view.deleteBackward(nil); keys.append("⌫")
            case 4:
                // Hangul as the input method types it: composed, recomposed, then committed.
                view.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                let marked = view.markedRange()
                let typed = try #require(view.textStorage).attributedSubstring(from: marked)
                let fresh = NSTextStorage(string: view.string)
                styler.style(fresh)
                #expect((typed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
                        == (fresh.attribute(.font, at: marked.location, effectiveRange: nil) as? NSFont)?.pointSize,
                        "seed \(seed) composing after \(keys.joined()) in \(view.string.debugDescription)")
                view.insertText("하", replacementRange: view.markedRange())
                keys.append("하")
            default:
                let piece = Self.pieces[Int.random(in: 0..<Self.pieces.count, using: &random)]
                view.insertText(piece, replacementRange: view.selectedRange())
                keys.append(piece)
            }
            let fresh = NSTextStorage(string: view.string)
            styler.style(fresh)
            let shown = Self.look(try #require(view.textStorage)), expected = Self.look(fresh)
            guard let i = shown.indices.first(where: { shown[$0] != expected[$0] }) else { continue }
            Issue.record("seed \(seed): after \(keys.joined()) char \(i) of \(view.string.debugDescription) is \(shown[i]), fresh \(expected[i])")
            return
        }
    }
}
