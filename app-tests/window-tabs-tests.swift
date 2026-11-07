import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// A window's own tabs: each keeps its history, the last one closes the window, and one moved out takes its history.
@MainActor
struct WindowTabsTests {
    @Test func eachTabKeepsItsOwnHistory() {
        let tabs = WindowTabs(Navigator())
        let first = tabs.selected
        tabs.current.go(Navigator.Entry(link: .place(.grades)))
        tabs.open(Navigator(Navigator.Entry(link: .course(graphTheory), course: graphTheory)))
        #expect(tabs.count == 2)
        #expect(tabs.current.screen == .course(graphTheory))
        #expect(!tabs.current.history.canGoBack)
        tabs.select(first)
        #expect(tabs.current.screen == .grades)
        #expect(tabs.current.backList.map(\.link) == [.place(.today)])
    }

    @Test func closingTheLastTabClosesTheWindow() {
        let tabs = WindowTabs(Navigator())
        var closed = false
        tabs.closeWindow = { closed = true }
        tabs.open()
        tabs.closeSelected()
        #expect(tabs.count == 1 && !closed)
        tabs.closeSelected()
        #expect(tabs.count == 1 && closed)
    }

    @Test func aTabMovedOutTakesItsHistory() {
        let tabs = WindowTabs(Navigator())
        let first = tabs.selected
        #expect(tabs.take(first) == nil)
        tabs.open(Navigator(Navigator.Entry(link: .place(.grades))))
        tabs.current.go(Navigator.Entry(link: .place(.people)))
        let moved = tabs.take(tabs.selected)
        #expect(moved?.backList.map(\.link) == [.place(.grades)])
        #expect(tabs.ids == [first])
        // A window made for it goes on from there, back included.
        let window = Navigator(history: moved?.history ?? LinkHistory(Navigator.Entry(link: .place(.today))))
        #expect(window.screen == .people && window.history.canGoBack)
    }

    @Test func closesTheOtherTabs() {
        let tabs = WindowTabs(Navigator())
        tabs.open()
        tabs.open()
        let kept = tabs.ids[1]
        tabs.closeOthers(than: kept)
        #expect(tabs.ids == [kept] && tabs.selected == kept)
        #expect(tabs.navigator(kept) != nil)
    }

    @Test func keepsTheRecentScreensAndLetsTheRestGo() {
        let tabs = WindowTabs(Navigator())
        var now = Date(timeIntervalSinceReferenceDate: 0)
        tabs.now = { now }
        tabs.policy = TabKeep.Policy(limit: 2, idle: 600)
        let first = tabs.selected
        for _ in 0..<3 {
            now += 10
            tabs.open()
        }
        // The front tab and the two most recently in front; the first went furthest back.
        #expect(tabs.alive.count == 3 && !tabs.alive.contains(first))
        // Waiting past the time lets the ones behind go.
        now += 601
        tabs.tick()
        #expect(tabs.alive == [tabs.selected])
        // In front again, a dropped tab is drawn again.
        tabs.select(first)
        #expect(tabs.alive.contains(first))
    }

    @Test func memoryPressureKeepsOnlyTheFront() {
        let tabs = WindowTabs(Navigator())
        tabs.open()
        tabs.open()
        #expect(tabs.alive.count == 3)
        tabs.dropBackground()
        #expect(tabs.alive == [tabs.selected])
    }

    @Test func aPlayingTabStaysBehindAndPausesFromTheStrip() {
        let tabs = WindowTabs(Navigator())
        let player = tabs.selected
        var paused = false
        tabs.play(player, pause: { paused = true })
        tabs.open()
        tabs.dropBackground()
        #expect(tabs.alive == [tabs.selected, player])
        tabs.pause(player)
        #expect(paused)
        // Stopped, it is kept no longer than any other tab.
        tabs.play(player, pause: nil)
        tabs.dropBackground()
        #expect(tabs.alive == [tabs.selected] && tabs.playing.isEmpty)
        // A closed tab's screen saying it stopped leaves nothing behind.
        tabs.play(player, pause: {})
        tabs.close(player)
        tabs.play(player, pause: nil)
        #expect(tabs.playing.isEmpty)
    }

    @Test func eachTabHasItsOwnTrail() {
        let tabs = WindowTabs(Navigator())
        let first = tabs.selected
        tabs.open()
        tabs.trail(first)?.set(Crumb(title: "노트"), level: 1, owner: UUID())
        #expect(tabs.trail(tabs.selected)?.crumbs.isEmpty == true)
        tabs.close(first)
        #expect(tabs.trail(first) == nil)
    }

    @Test func aMovedTabsWindowRequestSurvivesSaving() throws {
        var history = LinkHistory(Navigator.Entry(link: .place(.today)))
        history.visit(Navigator.Entry(link: .course(graphTheory), course: graphTheory))
        let request = WindowRequest(link: .course(graphTheory), course: graphTheory, history: history)
        let back = try JSONDecoder().decode(WindowRequest.self, from: JSONEncoder().encode(request))
        #expect(back.history == history && back.id == request.id)
    }
}

/// The tabs' place in the toolbar row as the window resizes: with room to spare it stays the same, so a live resize
/// doesn't redraw the tabs (#310), and it changes the frame the row runs out.
@MainActor
struct ToolbarRowTests {
    /// `onChange` runs synchronously, on the thread that made the change.
    final class Changes: @unchecked Sendable { var count = 0 }

    func row(width: CGFloat) -> ToolbarRow {
        let row = ToolbarRow()
        row.leadingX = 84
        row.trailingWidth = 328
        row.placeTrailing(width - 360, in: width)
        row.measures = ToolbarRow.Measures(front: 300, others: [120, 120, 32], more: 60, chrome: 44)
        row.windowWidth = width
        return row
    }

    @Test func aRoomyRowHoldsItsPlaceAsTheWindowResizes() {
        let row = row(width: 1400)
        let wide = row.placement
        #expect(wide.fit == TabFit.Layout(iconsOnly: false, shown: 3, hidden: 0) && wide.trail == nil)
        let changes = Changes()
        // The names fit down to 1220, where the tabs have just the 596 they take.
        for width in stride(from: 1400, through: 1220, by: -4) {
            withObservationTracking { _ = row.placement } onChange: { changes.count += 1 }
            row.windowWidth = CGFloat(width)
        }
        #expect(changes.count == 0)
        #expect(row.placement == wide)
    }

    @Test func itFollowsTheWidthAtOnceWhenTheRowRunsOut() {
        let row = row(width: 1400)
        // The search field stays where the row put it from the trailing edge, so the narrower width counts now, not
        // a turn later when the row reports the field's new place.
        row.windowWidth = 1180
        #expect(row.placement.fit == TabFit.Layout(iconsOnly: true, shown: 3, hidden: 0))
        // 276 for the tabs: the menu alone beside the tab in front, whose trail is held to 276 - 68 - 44 = 164.
        row.windowWidth = 900
        #expect(row.placement.fit == TabFit.Layout(iconsOnly: true, shown: 0, hidden: 3))
        #expect(row.placement.trail == 164)
        #expect(row.placement.lead == CGFloat(TabFit.lead(panelEdge: Theme.Size.sidebar, after: row.historyEnd, gap: Theme.Space.s)))
    }

    @Test func theStripNeverTakesTheSearchFieldsRoom() {
        // Wider than the row leaves it, the strip pushed the search field and the buttons into the toolbar's overflow
        // (#310). Down to where the tab in front's capsule, the menu and the + alone fill it.
        let row = row(width: 1400)
        let least = 44 + 60 + TabBar.gap * 2 + Theme.Size.toolbarButton
        for width in stride(from: 1400, through: 600, by: -4) {
            row.windowWidth = CGFloat(width)
            guard row.room >= least else { break }
            #expect(row.placement.width <= row.room, "at \(width)")
        }
    }

    @Test func aWiderSearchGroupTakesItsRoomFromTheTabs() {
        // A course's timer or a recording's clock widens the group without the window. Gone into the overflow menu it
        // has no place to report, so its width alone has to give the room back, or it never came out again.
        let row = row(width: 1000)
        let room = row.room
        let width = row.placement.width
        row.trailingWidth += 60
        row.placeTrailing(nil, in: 1000)
        #expect(row.room == room - 60)
        #expect(row.placement.width < width && row.placement.width <= row.room)
        // Back in the row, its place agrees.
        row.placeTrailing(1000 - 32 - row.trailingWidth, in: 1000)
        #expect(row.room == room - 60)
    }
}

/// What a tab behind the front one says: the thing it shows, else its screen; Today only its icon.
@MainActor
struct TabTitleTests {
    @Test func namesWhatTheTabShows() throws {
        let workspace = try fixtureWorkspace()
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))?.made)
        #expect(workspace.tabTitle(of: Navigator.Entry(link: AppLink(.exam, exam), course: graphTheory)) == "중간고사")
        let course = try #require(workspace.course(graphTheory))
        // A section alone says less than the course.
        #expect(workspace.tabTitle(of: Navigator.Entry(link: .course(graphTheory, page: .notes), course: graphTheory)) == course.title)
        #expect(workspace.tabTitle(of: Navigator.Entry(link: .place(.grades))) == String(localized: .rootNavGrades))
        #expect(workspace.tabTitle(of: Navigator.Entry(link: .place(.today))) == nil)
    }

    @Test func aCourseTabWearsTheCoursesMarkAndColor() throws {
        let workspace = try fixtureWorkspace()
        let place = workspace.placeCrumb(of: Navigator.Entry(link: .course(graphTheory), course: graphTheory))
        // Colors made per call compare unequal, so only that it has one.
        #expect(place.dot != nil)
        #expect(place.symbol == workspace.course(graphTheory)?.file.course.icon)
        #expect(workspace.placeCrumb(of: Navigator.Entry(link: .place(.today))).symbol == "house")
    }
}
