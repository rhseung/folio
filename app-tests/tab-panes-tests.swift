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
        let panes = TabPanes(Navigator())
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

    // No cap on the panes (2026-11-12 사용자): a fourth pane opens like the second, and a narrow row folds the rest
    // into bundles at its ends rather than a pane giving way.
    @Test func besideAlwaysOpensAPaneAndTheWidthFoldsTheRest() {
        let panes = TabPanes(Navigator())
        panes.openBeside(grades)
        panes.openBeside(people)
        panes.openBeside(codes)
        #expect(panes.count == 4 && panes.focus == 3)
        #expect(panes.navigators.map(\.current) == [Navigator.Entry(link: .place(.today)), grades, people, codes])
        // A target a pane already shows goes to that pane.
        panes.openBeside(Navigator.Entry(link: .place(.today)))
        #expect(panes.focus == 0 && panes.count == 4)
        // Room for two open beside a bundle: the run gives up its end pressed longer ago, twice, to the right bundle.
        panes.measure(900)
        #expect(panes.fold.run == 0...1 && panes.fold.right == [2, 3])
        panes.measure(2000)
        #expect(panes.fold.run == 0...3 && panes.folded.isEmpty)
        // A pane opened in a narrow row takes the run at once, from the width the row last had, and the pane it opened
        // beside goes to the left bundle.
        panes.measure(500)
        panes.openBeside(settings)
        #expect(panes.focus == 1 && panes.fold.run == 1...1 && panes.fold.left == [0] && panes.folded == [0, 2, 3, 4])
    }

    @Test func closingHandsTheFocusToThePanePressedLast() {
        let panes = TabPanes(Navigator())
        panes.openBeside(grades)
        panes.openBeside(people)
        panes.press(0)
        #expect(panes.close(0))
        #expect(panes.navigators.map(\.current) == [grades, people] && panes.focus == 1)
        #expect(panes.close(1) && !panes.close(0))
        #expect(panes.count == 1 && panes.shares == [1])
    }

    @Test func swappingKeepsEachPaneItsHistoryAndFocus() {
        let panes = TabPanes(Navigator())
        panes.openBeside(grades)
        let focused = panes.focused
        let trail = panes.focusedTrail
        panes.swap(0, 1)
        #expect(panes.focus == 0 && panes.focused === focused && panes.focusedTrail === trail)
    }

    @Test func draggingADividerDoesNotRedrawTheTabs() {
        // The toolbar's tabs draw from the focus and the panes; a share changing every frame of a drag must not touch
        // them, or the toolbar rebuilds its menu form each frame (#310).
        let panes = TabPanes(Navigator())
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
        let panes = TabPanes(Navigator())
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
        let panes = TabPanes(Navigator())
        panes.openBeside(grades)
        panes.openBeside(people)
        #expect(panes.folded.isEmpty)
        // The focused pane folds by hand: the focus goes to the pane pressed before it.
        panes.collapse(2)
        #expect(panes.collapsed == [2] && panes.folded == [2] && panes.focus == 1)
        // A row with room for every pane open still keeps it a strip.
        panes.measure(2000)
        #expect(panes.folded == [2])
        // Narrower, the pane pressed longer ago goes to the left bundle, never the focus; the one folded by hand
        // stays a strip in its place.
        panes.measure(500)
        #expect(panes.folded == [0, 2] && panes.fold.left == [0] && panes.fold.strips == [2])
        // The last open pane can't fold.
        panes.measure(2000)
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
        let window = try #require(TabPanes(histories: back.panes ?? [], shares: back.shares, focus: back.focus ?? 0))
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
        let tabs = WindowTabs(TabPanes(Navigator(grades)))
        let target = tabs.selected
        tabs.open(TabPanes(Navigator(people)))
        let source = tabs.selected
        tabs.select(target)
        tabs.merge(source, into: target, at: .leading)
        #expect(tabs.front?.navigators.map(\.current) == [people, grades])
    }

    @Test func aTabJoinsHoweverManyPanesEitherHas() throws {
        let tabs = WindowTabs(TabPanes(Navigator(grades)))
        let target = tabs.selected
        tabs.front?.openBeside(people)
        tabs.front?.openBeside(settings)
        tabs.open(TabPanes(Navigator(codes)))
        let source = tabs.selected
        tabs.panes(source)?.openBeside(Navigator.Entry(link: .place(.today)))
        #expect(tabs.canMerge(source, into: target) && !tabs.canMerge(target, into: target))
        tabs.merge(source, into: target)
        #expect(tabs.ids == [target] && tabs.panes(target)?.count == 5)
    }

    /// A drag lets go onto the panes' edge, within reach of it and below their top.
    @Test func aDragJoinsOnlyNearThePanesEdge() throws {
        let tabs = WindowTabs(TabPanes(Navigator(grades)))
        let target = tabs.selected
        tabs.open(TabPanes(Navigator(people)))
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
        for preset in PanePreset.builtIn { #expect(preset.title != preset.id) }
    }

    // MARK: A class's layout (#62)

    @Test func aClassLayoutComesBackAroundTheOnePane() throws {
        let note = Navigator.Entry(link: AppLink(.note, UUID()))
        let panes = TabPanes(Navigator())
        let navigator = panes.focused, id = panes.ids[0]
        var saved = try #require(PaneLayout(links: [grades.link, note.link, people.link], shares: [0.5, 0.3, 0.2]))
        saved.show(.read, in: 1)
        saved.press(1)
        #expect(panes.restore(saved, entries: [grades, note, people]))
        // The pane that opened the note keeps its history, its place among the screens and its columns.
        #expect(panes.count == 3 && panes.focus == 1)
        #expect(panes.focused === navigator && panes.ids[1] == id)
        #expect(navigator.current == note && navigator.backList == [Navigator.Entry(link: .place(.today))])
        #expect(panes.navigators.map(\.current) == [grades, note, people])
        let noteID = try #require(note.link.id)
        #expect(panes.noteModes == [nil, .read, nil] && panes.noteMode(of: noteID, pane: id) == .read)
        // A tab of more panes is the student's own arrangement: nothing changes.
        #expect(!panes.restore(saved, entries: [grades, note, people]))
        #expect(panes.count == 3)
    }

    @Test func aPaneWhoseItemIsGoneIsLeftOut() throws {
        let note = Navigator.Entry(link: AppLink(.note, UUID()))
        var saved = try #require(PaneLayout(links: [grades.link, note.link, people.link]))
        saved.press(1)
        let panes = TabPanes(Navigator())
        #expect(panes.restore(saved, entries: [nil, note, people]))
        #expect(panes.navigators.map(\.current) == [note, people] && panes.focus == 0)
        #expect(abs(panes.shares.reduce(0, +) - 1) < 1e-9)
        // Left with the note alone, the tab stays as it was.
        let alone = TabPanes(Navigator())
        #expect(!alone.restore(saved, entries: [nil, note, nil]))
        #expect(alone.count == 1 && alone.focused.current == Navigator.Entry(link: .place(.today)))
    }

    @Test func aPaneKeepsHowItShowsItsNote() throws {
        let note = AppLink(.note, UUID()), other = AppLink(.note, UUID())
        let panes = TabPanes(Navigator(Navigator.Entry(link: note)))
        panes.openBeside(grades)
        let id = panes.ids[0]
        let noteID = try #require(note.id), otherID = try #require(other.id)
        panes.show(.write, of: noteID, pane: id)
        #expect(panes.current.panes[0].noteMode == .write && panes.noteModes == [.write, nil])
        #expect(panes.noteMode(of: noteID, pane: id) == .write)
        // The pane gone on to another note starts that one from nothing.
        panes.navigators[0].go(Navigator.Entry(link: other))
        #expect(panes.noteMode(of: otherID, pane: id) == nil)
        #expect(panes.noteMode(of: noteID, pane: id) == nil)
        // A note the pane no longer shows can't set how the pane shows things.
        panes.show(.read, of: noteID, pane: id)
        #expect(panes.current.panes[0].noteMode == nil)
    }

    @Test func aRememberedLayoutOpensWithItsModesAndFolds() throws {
        let note = Navigator.Entry(link: AppLink(.note, UUID()))
        var layout = try #require(PaneLayout(links: [grades.link, note.link, people.link]))
        layout.show(.read, in: 1)
        layout.press(1)
        layout.collapse(0)
        let panes = try #require(TabPanes(layout: layout, entries: [grades, note, people]))
        #expect(panes.focus == 1 && panes.collapsed == [0] && panes.noteModes == [nil, .read, nil])
        #expect(panes.navigators.map(\.current) == [grades, note, people])
        #expect(TabPanes(layout: layout, entries: [grades, note]) == nil)
    }

    @Test func theDeviceKeepsAClassLayoutAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "folio-tests-\(UUID().uuidString)"))
        let session = UUID()
        let layout = try #require(PaneLayout(links: [grades.link, AppLink(.note, UUID())]))
        PaneMemoryStore(defaults: defaults).remember(layout, session: session)
        #expect(PaneMemoryStore(defaults: defaults).memory.layout(session: session) == layout)
    }

    @Test func aFixtureRunKeepsItsLayoutsApartFromTheUsers() throws {
        let fixture = ["FOLIO_GIST": "/tmp/folio-tests-\(UUID().uuidString)"]
        let other = ["FOLIO_GIST": "/tmp/folio-tests-\(UUID().uuidString)"]
        let session = UUID()
        let layout = try #require(PaneLayout(links: [grades.link, AppLink(.note, UUID())]))
        let before = UserDefaults.standard.data(forKey: PaneMemoryStore.key)
        PaneMemoryStore.forThisRun(environment: fixture).remember(layout, session: session)
        #expect(PaneMemoryStore.forThisRun(environment: fixture).memory.layout(session: session) == layout)
        #expect(PaneMemoryStore.forThisRun(environment: other).memory.layout(session: session) == nil)
        #expect(UserDefaults.standard.data(forKey: PaneMemoryStore.key) == before)
        let fixtures = try #require(UserDefaults(suiteName: "folio-fixtures"))
        for key in fixtures.dictionaryRepresentation().keys where key.hasPrefix(PaneMemoryStore.key + ".") { fixtures.removeObject(forKey: key) }
    }
}
