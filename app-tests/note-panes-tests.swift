import Testing
@testable import Folio

struct NotePanesTests {
    @Test func startsSideBySideAndShowsSourceWhenNarrow() {
        let panes = NotePanes()
        #expect(panes.shown(wide: true) == .split)
        #expect(panes.shown(wide: false) == .write)
    }

    @Test func aWideChoiceHoldsAtAnyWidthButSplit() {
        var panes = NotePanes()
        panes.choose(.read)
        #expect(panes.shown(wide: true) == .read)
        #expect(panes.shown(wide: false) == .read)
        panes.choose(.write)
        #expect(panes.shown(wide: true) == .write)
        #expect(panes.shown(wide: false) == .write)
    }

    @Test func toggleReturnsToTheLastWayOfWriting() {
        var panes = NotePanes()
        panes.toggle()
        #expect(panes.mode == .read)
        panes.toggle()
        #expect(panes.mode == .split)

        panes.choose(.write)
        panes.toggle()
        panes.toggle()
        #expect(panes.mode == .write)
    }

    @Test func writingWhileNarrowKeepsTheSplitForWhenItWidens() {
        var panes = NotePanes()
        panes.chooseNarrow(.read)
        panes.chooseNarrow(.write)
        #expect(panes.shown(wide: false) == .write)
        #expect(panes.shown(wide: true) == .split)
    }

    @Test func opensAsRemembered() {
        let read = NotePanes(remembered: .read)
        #expect(read.mode == .read)
        var toggled = read
        toggled.toggle()
        #expect(toggled.mode == .split)
        #expect(NotePanes(remembered: .write).shown(wide: true) == .write)
    }
}
