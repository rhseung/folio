import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteLayoutTests {
    // 패널이 아니라 그림의 폭을 쓴다. 스크롤 막대가 항상 보이는 환경(마우스를 쓰는 Mac, CI 러너)에서는 스크롤 막대가 노트의 폭을 차지하기 때문이다.
    static func column(_ shot: Pixels) -> ClosedRange<CGFloat> {
        let width = CGFloat(shot.width)
        let left = (width - min(NoteLook.measure, width)) / 2 + NoteLook.margin
        return left...(width - left)
    }

    // 가장자리마다 안티에일리어싱 1pt를 허용한다.
    static func outside(_ shot: Pixels) -> (left: Int, right: Int) {
        let column = Self.column(shot)
        let height = CGFloat(shot.height)
        return (
            shot.ink(in: CGRect(x: 0, y: 0, width: column.lowerBound - 1, height: height)),
            shot.ink(in: CGRect(x: column.upperBound + 1, y: 0, width: CGFloat(shot.width) - column.upperBound - 1, height: height))
        )
    }

    static func inkedRows(_ shot: Pixels) -> [Bool] {
        let column = Self.column(shot)
        return (0..<shot.height).map {
            shot.ink(in: CGRect(x: column.lowerBound, y: CGFloat($0), width: column.upperBound - column.lowerBound, height: 1)) > 0
        }
    }

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

    // 노트의 두 줄이 이만큼 떨어지는 일은 없고, 그림에 보이지 않는 위젯이 가장 큰 간격이다.
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
