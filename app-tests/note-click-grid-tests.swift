import AppKit
import Foundation
import Testing
@testable import Folio

/// Points across the whole panel, as it opens and scrolled, each clicked: every one must reach the note, or what the
/// note shows there (a widget, a block that scrolls sideways). In the edit view a click puts the caret where it lands.
/// The lower half of a long note once took no clicks at all (#263).
@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteClickGridTests {
    static let step: CGFloat = 40

    static func grid(_ size: CGSize, step: CGFloat = step) -> [[CGPoint]] {
        stride(from: step / 2, to: size.width, by: step).map { x in
            stride(from: step / 2, to: size.height, by: step).map { CGPoint(x: x, y: $0) }
        }
    }

    /// Opened, scrolled to the end, then halfway back: what each place shows is checked by `check`.
    static func places(_ bench: NoteBench, _ check: (String) async -> Void) async {
        await bench.settle()
        await check("opened")
        await bench.scrollToEnd()
        let end = bench.scrollY
        await check("at the end")
        await bench.scroll(to: (end / 2).rounded())
        await check("halfway")
    }

    @Test(arguments: NoteShot.light)
    func everyPointHitsTheNote(_ shot: NoteShot) async {
        let bench = shot.bench(NoteBench.longNote)
        await Self.places(bench) { place in
            let points = Self.grid(bench.size).flatMap { $0 }
            let missed = points.compactMap { p -> String? in
                switch bench.hit(at: p) {
                case .note, .scroller: nil
                case .other(let what): "(\(Int(p.x)), \(Int(p.y))) \(what)"
                }
            }
            #expect(missed.isEmpty, "\(shot.name) \(place): \(missed.count) of \(points.count) points missed the note, as \(missed.prefix(6))")
        }
    }

    /// No line is further than this from a point beside it: a heading's gap above, a paragraph's below.
    static let reach: CGFloat = 56

    /// Each point is a full mouse-down in the text view, so the caret grid is coarser than the hit grid.
    static let caretStep: CGFloat = 80

    @Test(arguments: NoteShot.widths)
    func aClickPutsTheCaretWhereItLands(_ width: Int) async {
        let bench = NoteBench(.edit, NoteBench.longNote, width: CGFloat(width))
        await Self.places(bench) { place in
            // The text view exists only once SwiftUI has placed it.
            bench.focus()
            let length = (bench.text as NSString).length
            let end = bench.rect(of: NSRange(location: length, length: 0))
            var wrong: [String] = []
            for column in Self.grid(bench.size, step: Self.caretStep) {
                var above = 0
                for p in column {
                    guard bench.hit(at: p) == .note else { continue }
                    // The caret starts at the far end of the note, so a click that does nothing leaves it out of reach.
                    // Not a selection: a click inside one waits to see whether a drag starts, which timed the test out.
                    bench.perform(above < length / 2 ? #selector(NSResponder.moveToEndOfDocument(_:)) : #selector(NSResponder.moveToBeginningOfDocument(_:)))
                    let scrolled = bench.scrollY
                    bench.click(at: p)
                    let at = "(\(Int(p.x)), \(Int(p.y)))"
                    if abs(bench.scrollY - scrolled) > 0.5 {
                        wrong.append("\(at) moved the page by \(bench.scrollY - scrolled)")
                        bench.jump(to: scrolled)
                    }
                    guard let caret = bench.caret else {
                        wrong.append("\(at) selected text")
                        continue
                    }
                    if p.y > end.maxY {
                        if caret.location != length { wrong.append("\(at) past the end put the caret at \(caret.location) of \(length)") }
                    } else {
                        let off = p.y < caret.rect.minY ? caret.rect.minY - p.y : max(0, p.y - caret.rect.maxY)
                        if off > Self.reach { wrong.append("\(at) put the caret \(Int(off)) points away, at \(Int(caret.rect.minY))") }
                    }
                    // Lower on the panel is never earlier in the note.
                    if caret.location < above { wrong.append("\(at) put the caret at \(caret.location), before \(above) above it") }
                    above = caret.location
                }
            }
            #expect(wrong.isEmpty, "\(width) \(place): \(wrong.count) clicks went wrong, as \(wrong.prefix(6))")
        }
    }
}
