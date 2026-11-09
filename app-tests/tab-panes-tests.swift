import FolioDomain
import Foundation
import Testing
@testable import Folio

/// A tab's panes (#62): each keeps its own history, the tab's place follows the focused one, and "옆 칸에 열기" opens
/// a pane beside the one that asked.
@MainActor
struct TabPanesTests {
    let grades = Navigator.Entry(link: .place(.grades))
    let people = Navigator.Entry(link: .place(.people))
    let codes = Navigator.Entry(link: .place(.codes))
    let settings = Navigator.Entry(link: .place(.settings))

    @Test func besideOpensARightNeighborAndFocusesIt() {
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        #expect(panes.count == 2 && panes.focus == 1)
        #expect(panes.navigators.map(\.current) == [Navigator.Entry(link: .place(.today)), grades])
        // The new pane starts its own history.
        #expect(!panes.focused.history.canGoBack)
        // From the first pane, the next one opens right of it, between the two.
        panes.openBeside(people, from: panes.navigators[0])
        #expect(panes.navigators.map(\.current) == [Navigator.Entry(link: .place(.today)), people, grades])
        #expect(panes.trails.count == 3 && Set(panes.ids).count == 3)
    }

    @Test func atTheLimitThePaneUsedLongestAgoGoesOn() {
        let panes = TabPanes(Navigator(), limit: 2)
        panes.openBeside(grades)
        panes.press(0)
        panes.openBeside(people)
        // The grades pane was pressed longest ago: it goes on to people, with grades a step back.
        #expect(panes.count == 2 && panes.focus == 1)
        #expect(panes.focused.current == people && panes.focused.backList == [grades])
        // A target a pane already shows goes to that pane.
        panes.openBeside(Navigator.Entry(link: .place(.today)))
        #expect(panes.focus == 0 && panes.count == 2)
    }

    @Test func closingHandsTheFocusToThePanePressedLast() {
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        panes.openBeside(people)
        panes.press(0)
        #expect(panes.close(0))
        #expect(panes.navigators.map(\.current) == [grades, people] && panes.focus == 1)
        #expect(panes.close(1) && !panes.close(0))
        #expect(panes.count == 1 && panes.shares == [1])
    }

    @Test func swappingKeepsEachPaneItsHistoryAndFocus() {
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        let focused = panes.focused
        let trail = panes.focusedTrail
        panes.swap(0, 1)
        #expect(panes.focus == 0 && panes.focused === focused && panes.focusedTrail === trail)
    }

    @Test func draggingADividerDoesNotRedrawTheTabs() {
        // The toolbar's tabs draw from the focus and the panes; a share changing every frame of a drag must not touch
        // them, or the toolbar rebuilds its menu form each frame (#310).
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        final class Changes: @unchecked Sendable { var count = 0 }
        let changes = Changes()
        withObservationTracking {
            _ = panes.focus
            _ = panes.ids
            _ = panes.navigators
            _ = panes.trails
        } onChange: { changes.count += 1 }
        panes.resize(divider: 0, to: 0.3)
        panes.press(1)
        #expect(changes.count == 0)
        #expect(abs(panes.shares[0] - 0.3) < 1e-9)
    }

    @Test func evenSharesTheWidthWithoutRedrawingTheTabs() {
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        panes.openBeside(people)
        panes.resize(divider: 0, to: 0.2)
        final class Changes: @unchecked Sendable { var count = 0 }
        let changes = Changes()
        withObservationTracking {
            _ = panes.focus
            _ = panes.ids
        } onChange: { changes.count += 1 }
        panes.even()
        #expect(panes.shares.allSatisfy { abs($0 - 1.0 / 3) < 1e-9 })
        #expect(changes.count == 0 && panes.focus == 2)
    }

    @Test func aPaneFoldedByHandStaysAStripAtAnyWidth() {
        let panes = TabPanes(Navigator(), limit: 3)
        panes.openBeside(grades)
        panes.openBeside(people)
        #expect(panes.folded.isEmpty)
        // The focused pane folds by hand: the focus goes to the pane pressed before it.
        panes.collapse(2)
        #expect(panes.collapsed == [2] && panes.folded == [2] && panes.focus == 1)
        // A row with room for one more open pane still keeps it a strip.
        panes.room = [2, 3]
        #expect(panes.folded == [2])
        // Narrower, the room folds another, never the focus.
        panes.room = [1, 1]
        #expect(panes.folded == [0, 2])
        // The last open pane can't fold.
        panes.room = [2, 3]
        panes.collapse(0)
        #expect(!panes.canCollapse(1))
        // Pressing a strip opens it.
        panes.press(2)
        #expect(panes.collapsed == [0] && panes.focus == 2)
    }

    @Test func theWindowFollowsTheFocusedPane() {
        let tabs = WindowTabs(Navigator())
        let panes = tabs.front!
        panes.openBeside(grades)
        #expect(tabs.current === panes.navigators[1])
        #expect(tabs.trail(tabs.selected) === panes.trails[1])
        panes.press(0)
        #expect(tabs.current.screen == .today)
        // A pane's screen finds its tab even behind another.
        let pane = panes.navigators[1]
        tabs.open()
        #expect(tabs.panes(holding: pane) === panes)
    }

    @Test func aTabOfSeveralPanesMovesToAWindowWhole() throws {
        let tabs = WindowTabs(Navigator())
        tabs.open(Navigator(grades))
        let panes = try #require(tabs.front)
        panes.focused.go(people)
        panes.openBeside(codes)
        panes.resize(divider: 0, to: 0.7)
        panes.press(0)
        let moved = try #require(tabs.take(tabs.selected))
        var request = WindowRequest(link: moved.focused.current.link, history: moved.focused.history)
        request.panes = moved.navigators.map(\.history)
        request.shares = moved.shares
        request.focus = moved.focus
        let back = try JSONDecoder().decode(WindowRequest.self, from: JSONEncoder().encode(request))
        let window = try #require(TabPanes(histories: back.panes ?? [], shares: back.shares, focus: back.focus ?? 0, limit: 3))
        #expect(window.navigators.map(\.current) == [people, codes])
        #expect(window.focus == 0 && window.focused.backList == [grades])
        #expect(abs(window.shares[0] - 0.7) < 1e-9)
    }

    /// "옆 칸으로 합치기" (2026-11-09 사용자): the other tab's pane joins with its history and its focus, and its tab
    /// closes; the tab it joined comes to the front.
    @Test func anotherTabJoinsBesideTheFocusWithItsHistory() throws {
        let tabs = WindowTabs(Navigator(grades))
        let front = try #require(tabs.front)
        let target = tabs.selected
        tabs.open(Navigator(people))
        let source = tabs.selected
        tabs.navigator(source)?.go(codes)
        tabs.select(target)
        #expect(tabs.canMerge(source, into: target))
        tabs.merge(source, into: target)
        #expect(tabs.ids == [target] && tabs.selected == target)
        #expect(front.navigators.map(\.current) == [grades, codes] && front.focus == 1)
        #expect(front.focused.backList == [people])
        #expect(Set(front.ids).count == 2 && front.trails.count == 2)
    }

    @Test func aTabJoinsAtTheEdgeItWasDroppedOn() throws {
        let tabs = WindowTabs(TabPanes(Navigator(grades), limit: 3))
        let target = tabs.selected
        tabs.open(TabPanes(Navigator(people), limit: 3))
        let source = tabs.selected
        tabs.select(target)
        tabs.merge(source, into: target, at: .leading)
        #expect(tabs.front?.navigators.map(\.current) == [people, grades])
    }

    @Test func aTabThatWouldNotFitIsLeftOpen() throws {
        let tabs = WindowTabs(TabPanes(Navigator(grades), limit: 2))
        let target = tabs.selected
        tabs.front?.openBeside(people)
        tabs.open(TabPanes(Navigator(codes), limit: 2))
        let source = tabs.selected
        #expect(!tabs.canMerge(source, into: target) && !tabs.canMerge(target, into: target))
        tabs.merge(source, into: target)
        #expect(tabs.ids == [target, source] && tabs.panes(target)?.count == 2)
    }

    /// A drag lets go onto the panes' edge, within reach of it and below their top, for a tab that fits.
    @Test func aDragJoinsOnlyNearThePanesEdge() throws {
        let tabs = WindowTabs(TabPanes(Navigator(grades), limit: 3))
        let target = tabs.selected
        tabs.open(TabPanes(Navigator(people), limit: 3))
        let source = tabs.selected
        tabs.select(target)
        tabs.contentFrame = CGRect(x: 200, y: 48, width: 1000, height: 700)
        #expect(tabs.drop(for: source, at: CGPoint(x: 210, y: 300)) == WindowTabs.MergeDrop(edge: .leading, share: 0.5))
        #expect(tabs.drop(for: source, at: CGPoint(x: 1190, y: 300))?.edge == .trailing)
        #expect(tabs.drop(for: source, at: CGPoint(x: 700, y: 300)) == nil)
        #expect(tabs.drop(for: source, at: CGPoint(x: 210, y: 20)) == nil)
        #expect(tabs.drop(for: target, at: CGPoint(x: 210, y: 300)) == nil)
    }

    @Test func eachPresetHasAName() {
        for preset in PanePreset.builtIn { #expect(preset.name != preset.id) }
    }
}
