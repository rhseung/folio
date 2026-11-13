import Foundation
import Testing
@testable import Folio

/// The note views' layout, read off what they draw: blocks stay in the text column, a note just opened is drawn down
/// to the bottom of the panel, and the page scrolls on past the note's end. Pictures compared with references
/// (`NoteScreenTests`) catch the rest, but they're made anew when the look changes; these hold through any look.
@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteLayoutTests {
    /// The text column of a picture of the panel, its margins left out. It's the picture's width, not the panel's:
    /// where scrollers always show (a Mac with a mouse, the CI runner) they take their width off the note.
    static func column(_ shot: Pixels) -> ClosedRange<CGFloat> {
        let width = CGFloat(shot.width)
        let left = (width - min(NoteLook.measure, width)) / 2 + NoteLook.margin
        return left...(width - left)
    }

    /// Ink left and right of the column, a point of antialiasing allowed at each edge.
    static func outside(_ shot: Pixels) -> (left: Int, right: Int) {
        let column = Self.column(shot)
        let height = CGFloat(shot.height)
        return (shot.ink(in: CGRect(x: 0, y: 0, width: column.lowerBound - 1, height: height)),
                shot.ink(in: CGRect(x: column.upperBound + 1, y: 0, width: CGFloat(shot.width) - column.upperBound - 1, height: height)))
    }

    /// Whether each row of the column has ink in it, top down.
    static func inkedRows(_ shot: Pixels) -> [Bool] {
        let column = Self.column(shot)
        return (0..<shot.height).map { shot.ink(in: CGRect(x: column.lowerBound, y: CGFloat($0), width: column.upperBound - column.lowerBound, height: 1)) > 0 }
    }

    /// The tallest run of rows with no ink, from the top down to `end`: where it starts and how tall it is.
    static func longestBlank(_ rows: [Bool], to end: Int) -> (from: Int, height: Int) {
        var best = (from: 0, height: 0), start: Int?
        for y in 0...min(end, rows.count) {
            if y < min(end, rows.count), !rows[y] {
                start = start ?? y
            } else if let s = start {
                if y - s > best.height { best = (s, y - s) }
                start = nil
            }
        }
        return best
    }

    /// No two lines of a note stand this far apart; the widget, which the pictures don't show, is the tallest gap.
    static let gap = 240

    @Test(arguments: NoteShot.light)
    func everyBlockStaysInTheColumn(_ shot: NoteShot) async {
        let all = shot.bench(NoteBench.allMarkdown)
        await all.settle()
        let whole = Self.outside(await all.wholeNote())
        #expect(whole.left == 0 && whole.right == 0, "every construct, \(shot.name): ink outside the column \(whole)")

        let long = shot.bench(NoteBench.longNote)
        await long.settle()
        let opened = Self.outside(long.snapshot())
        #expect(opened.left == 0 && opened.right == 0, "long note opened, \(shot.name): ink outside the column \(opened)")
        await long.scrollToEnd()
        let end = Self.outside(long.snapshot())
        #expect(end.left == 0 && end.right == 0, "long note at its end, \(shot.name): ink outside the column \(end)")
    }

    /// A note just opened showed only the top of the panel until it was scrolled (#263).
    @Test(arguments: NoteShot.all)
    func theWholePanelIsDrawnOnOpen(_ shot: NoteShot) async {
        let bench = shot.bench(NoteBench.longNote)
        await bench.settle()
        let opened = Self.inkedRows(bench.snapshot())
        let blank = Self.longestBlank(opened, to: opened.count)
        #expect(blank.height < Self.gap, "opened: nothing drawn for \(blank.height) points from \(blank.from) of \(opened.count)")
        #expect(opened.suffix(opened.count / 4).contains(true), "opened: the bottom quarter of the panel is empty")

        await bench.scrollToEnd()
        let end = bench.scrollY
        await bench.scroll(to: end / 2)
        let middle = Self.inkedRows(bench.snapshot())
        let gap = Self.longestBlank(middle, to: middle.count)
        #expect(gap.height < Self.gap, "scrolled: nothing drawn for \(gap.height) points from \(gap.from) of \(middle.count)")
    }

    /// One writes at the note's end, so the page goes on past it: the editor brings the last line up to the middle
    /// of the panel, the preview further, to follow the editor.
    @Test(arguments: NoteShot.light)
    func thePageScrollsPastTheNotesEnd(_ shot: NoteShot) async throws {
        let bench = shot.bench(NoteBench.longNote)
        await bench.settle()
        #expect(bench.scrollY == 0)
        await bench.scrollToEnd()
        #expect(bench.scrollY > 0, "the long note should scroll")
        let rows = Self.inkedRows(bench.snapshot())
        let last = try #require(rows.lastIndex(of: true), "nothing drawn at the end")
        let room = rows.count - last
        #expect(room >= rows.count / 3, "\(shot.name): \(room) points below the last line of \(rows.count)")
        let blank = Self.longestBlank(rows, to: last)
        #expect(blank.height < Self.gap, "at the end: nothing drawn for \(blank.height) points from \(blank.from)")
    }
}
