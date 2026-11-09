@testable import Folio
import Foundation
import Testing

@MainActor
struct NoteOutlineModelTests {
    let text = "# 제목\n\n본문\n\n## 하나\n\n#### 깊은\n\n## 둘\n\n끝"

    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    @Test func scrollingMarksTheHeadingAtTheTop() {
        let model = NoteOutlineModel()
        model.read(text)
        #expect(model.rows.map(\.title) == ["제목", "하나", "둘"])
        #expect(model.rows.first(where: \.marked)?.title == "제목")
        model.views.previewScrolled(9)
        #expect(model.rows.first(where: \.marked)?.title == "둘")
        // Inside a folded heading, the one it folds under is marked.
        model.views.previewScrolled(7)
        #expect(model.rows.first(where: \.marked)?.title == "하나")
    }

    @Test func aFoldedHeadingOpensAndStaysOpenAsTheNoteIsWritten() throws {
        let model = NoteOutlineModel()
        model.read(text)
        let one = try #require(model.rows.first { $0.title == "하나" })
        #expect(one.folds && !one.open)
        model.toggle(one.index)
        #expect(model.rows.map(\.title) == ["제목", "하나", "깊은", "둘"])
        model.read("## 앞에 쓴 제목\n\n" + text)
        #expect(model.rows.map(\.title) == ["앞에 쓴 제목", "제목", "하나", "깊은", "둘"])
    }

    @Test func aJumpHoldsItsMarkAgainstTheScrollItMakes() throws {
        let clock = Clock()
        let model = NoteOutlineModel(now: { clock.now })
        model.read(text)
        let two = try #require(model.rows.first { $0.title == "둘" })
        model.jump(two.index)
        // The note's end can't come to the top, so the scroll stops above the heading.
        model.views.previewScrolled(5)
        #expect(model.rows.first(where: \.marked)?.title == "둘")
        clock.now += 1
        model.views.previewScrolled(5)
        #expect(model.rows.first(where: \.marked)?.title == "하나")
    }

    @Test func theOutlineDocksWhereThereIsRoom() {
        let narrow = NoteOutlineFit(width: NoteLook.measure + Theme.Size.noteOutline - 1)
        #expect(!narrow.docks(.read) && !narrow.docks(.split))
        let one = NoteOutlineFit(width: NoteLook.measure + Theme.Size.noteOutline)
        #expect(one.docks(.write) && !one.docks(.split))
        #expect(NoteOutlineFit(width: NotePanes.sideBySide + Theme.Size.noteOutline).docks(.split))
    }
}
