import FolioDomain
import FolioFixtures
import SwiftUI
import Testing

@testable import Folio

@MainActor
struct ColumnFitTests {
    @Test func docksOnlyWithRoomAndNotHiddenByHand() {
        #expect(ColumnFit(roomy: true, collapsed: false).docked)
        #expect(!ColumnFit(roomy: true, collapsed: true).docked)
        #expect(!ColumnFit(roomy: false, collapsed: false).docked)
        #expect(!ColumnFit(roomy: false, collapsed: true).docked)
    }

    @Test func showingAgainDocksWhereItFitsAndOpensOverThePageWhereItDoesnt() {
        #expect(ColumnFit(roomy: true, collapsed: true).show == .dock)
        #expect(ColumnFit(roomy: false, collapsed: true).show == .overlay)
        #expect(ColumnFit(roomy: false, collapsed: false).show == .overlay)
    }

    @Test func aGrowingListWithNothingBesideIsThePageOnlyForWantOfRoom() {
        let empty = ColumnFold.list(showingPage: false)
        #expect(ColumnFit(roomy: false, collapsed: false, fold: empty).listAlone)
        #expect(ColumnFit(roomy: false, collapsed: true, fold: empty).listAlone)
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

        let other = TabPanes(Navigator(people), memory: memory)
        #expect(panes.close(1) && panes.merge(other, at: 0))
        #expect(panes.columns[1] === hidden && !panes.columns[0].isCollapsed(.people))

        let window = try #require(
            TabPanes(
                histories: panes.navigators.map(\.history), shares: panes.shares, focus: 0,
                columns: [[], hidden.names], memory: memory))
        #expect(!window.columns[0].isCollapsed(.people) && window.columns[1].isCollapsed(.people))
        #expect(memory.pane(nil).collapsed == memory.last && memory.pane(["gone", "people"]).collapsed == [.people])
    }
}
