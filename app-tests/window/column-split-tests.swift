import FolioDomain
import FolioFixtures
import SwiftUI
import Testing
@testable import Folio

/// Where a list column is (#62): docked where it fits and isn't hidden by hand, otherwise folded behind the button at
/// the page's corner, which docks it back where it fits and opens it over the page where it doesn't.
@MainActor
struct ColumnFitTests {
    @Test func docksOnlyWithRoomAndNotHiddenByHand() {
        #expect(ColumnFit(roomy: true, collapsed: false).docked)
        #expect(!ColumnFit(roomy: true, collapsed: true).docked)
        #expect(!ColumnFit(roomy: false, collapsed: false).docked)
        #expect(!ColumnFit(roomy: false, collapsed: true).docked)
    }

    @Test func showingAgainDocksWhereItFitsAndOpensOverThePageWhereItDoesnt() {
        // Hidden by hand with room: back beside the page, which undoes the choice.
        #expect(ColumnFit(roomy: true, collapsed: true).show == .dock)
        // Too narrow, hidden by hand or not: over the page for the moment, the choice kept.
        #expect(ColumnFit(roomy: false, collapsed: true).show == .overlay)
        #expect(ColumnFit(roomy: false, collapsed: false).show == .overlay)
    }

    @Test func aGrowingListWithNothingBesideIsThePageOnlyForWantOfRoom() {
        let empty = ColumnFold.list(showingPage: false)
        #expect(ColumnFit(roomy: false, collapsed: false, fold: empty).listAlone)
        #expect(ColumnFit(roomy: false, collapsed: true, fold: empty).listAlone)
        // Hidden by hand where it fits, the page shows its empty state and the button brings the list back.
        #expect(!ColumnFit(roomy: true, collapsed: true, fold: empty).listAlone)
        #expect(ColumnFit(roomy: true, collapsed: true, fold: empty).showsPage)
        #expect(!ColumnFit(roomy: false, collapsed: false, fold: .list(showingPage: true)).listAlone)
        #expect(!ColumnFit(roomy: false, collapsed: false, fold: .sections).listAlone)
    }

    @Test func handHidingIsRememberedPerKindAsTheLastChoice() throws {
        let suite = "folio.column-fit-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = ColumnMemory(defaults: defaults).newPane()
        prefs.set(.courseSections, collapsed: true)
        #expect(prefs.isCollapsed(.courseSections))
        #expect(!prefs.isCollapsed(.people))
        // The app opened again starts its panes from it.
        #expect(ColumnMemory(defaults: defaults).newPane().isCollapsed(.courseSections))
        prefs.set(.courseSections, collapsed: false)
        #expect(!ColumnMemory(defaults: defaults).newPane().isCollapsed(.courseSections))
    }

    @Test func prefsWithoutAMemoryDontTouchTheLastChoice() {
        let before = ColumnMemory.shared.last
        let prefs = ColumnPrefs(collapsed: [.people])
        #expect(prefs.isCollapsed(.people))
        prefs.set(.settingsTabs, collapsed: !before.contains(.settingsTabs))
        #expect(prefs.isCollapsed(.settingsTabs) != before.contains(.settingsTabs))
        #expect(ColumnMemory.shared.last == before)
    }
}

/// Each tab and each pane of a split keeps its own hidden columns; a new one starts from the last choice
/// (2026-11-10 사용자).
@MainActor
struct PaneColumnTests {
    let grades = Navigator.Entry(link: .place(.grades))
    let people = Navigator.Entry(link: .place(.people))

    @Test func twoPanesKeepTheirOwnAndANewPaneTakesTheLastChoice() {
        let memory = ColumnMemory(defaults: nil)
        let panes = TabPanes(Navigator(), memory: memory)
        panes.openBeside(grades)
        let (left, right) = (panes.columns[0], panes.columns[1])
        #expect(left !== right)
        left.set(.courseSections, collapsed: true)
        #expect(left.isCollapsed(.courseSections) && !right.isCollapsed(.courseSections))
        // The next pane, and the next tab, start from the choice made last.
        panes.openBeside(people)
        #expect(panes.columns[2].isCollapsed(.courseSections))
        #expect(TabPanes(Navigator(), memory: memory).columns[0].isCollapsed(.courseSections))
        right.set(.courseSections, collapsed: false)
        #expect(left.isCollapsed(.courseSections))
        #expect(!TabPanes(Navigator(), memory: memory).columns[0].isCollapsed(.courseSections))
    }

    @Test func aPaneKeepsItsColumnsAsItMoves() throws {
        let memory = ColumnMemory(defaults: nil)
        let panes = TabPanes(Navigator(), memory: memory)
        panes.openBeside(grades)
        let hidden = panes.columns[1]
        hidden.set(.people, collapsed: true)
        memory.remember(.people, collapsed: false)
        panes.swap(0, 1)
        #expect(panes.columns[0] === hidden)

        // Joining another tab, each pane brings its own.
        let other = TabPanes(Navigator(people), memory: memory)
        #expect(panes.close(1) && panes.merge(other, at: 0))
        #expect(panes.columns[1] === hidden && !panes.columns[0].isCollapsed(.people))

        // Out to a window of its own: what it had hidden goes with it, a pane without any starts from the last choice.
        let window = try #require(TabPanes(histories: panes.navigators.map(\.history), shares: panes.shares, focus: 0,
                                           columns: [[], hidden.names], memory: memory))
        #expect(!window.columns[0].isCollapsed(.people) && window.columns[1].isCollapsed(.people))
        #expect(memory.pane(nil).collapsed == memory.last && memory.pane(["gone", "people"]).collapsed == [.people])
    }
}
