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
