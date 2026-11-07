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

    @Test func handHidingIsRememberedPerKind() throws {
        let suite = "folio.column-fit-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = ColumnPrefs(defaults: defaults)
        prefs.set(.courseSections, collapsed: true)
        #expect(prefs.isCollapsed(.courseSections))
        #expect(!prefs.isCollapsed(.people))
        // Another window reads the same choice.
        #expect(ColumnPrefs(defaults: defaults).isCollapsed(.courseSections))
        prefs.set(.courseSections, collapsed: false)
        #expect(!ColumnPrefs(defaults: defaults).isCollapsed(.courseSections))
    }

    @Test func inMemoryPrefsDontTouchTheDefaults() {
        let prefs = ColumnPrefs(defaults: nil, collapsed: [.people])
        #expect(prefs.isCollapsed(.people))
        prefs.set(.settingsTabs, collapsed: true)
        #expect(prefs.isCollapsed(.settingsTabs))
    }
}
