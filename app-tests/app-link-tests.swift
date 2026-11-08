import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// One window's history: every way of moving goes through `go`, and the same item at another page is one step.
@MainActor
struct NavigatorTests {
    @Test func movesBackAndForwardThroughWhereTheWindowWas() {
        let navigator = Navigator()
        let course = Navigator.Entry(link: .course(graphTheory), course: graphTheory)
        let grades = Navigator.Entry(link: .place(.grades))
        navigator.go(course)
        navigator.go(grades)
        #expect(navigator.screen == .grades)
        #expect(navigator.backList.map(\.link) == [.course(graphTheory), .place(.today)])
        navigator.back(2)
        #expect(navigator.screen == .today)
        #expect(navigator.forwardList.map(\.link) == [.course(graphTheory), .place(.grades)])
        navigator.forward()
        #expect(navigator.screen == .course(graphTheory))
        // A new move drops what was ahead, as in a browser.
        navigator.go(Navigator.Entry(link: .place(.people)))
        #expect(navigator.forwardList.isEmpty)
    }

    @Test func anotherPageOfTheSameFileIsTheSameStep() {
        let navigator = Navigator()
        let file = AppLink(.material, UUID())
        navigator.go(Navigator.Entry(link: file.with(.page(3)), course: graphTheory))
        navigator.go(Navigator.Entry(link: file.with(.page(12)), course: graphTheory))
        #expect(navigator.current.link == file.with(.page(12)))
        #expect(navigator.backList.count == 1)
        #expect(navigator.screen == .course(graphTheory))
    }

    /// Listening moves a replay's address every few seconds; none of it is a step to go back through.
    @Test func anotherMomentOfTheSameRecordingIsTheSameStep() {
        let navigator = Navigator()
        let replay = AppLink(.recording, UUID())
        navigator.go(Navigator.Entry(link: replay, course: graphTheory))
        for t in stride(from: 5, through: 60, by: 5) { navigator.go(Navigator.Entry(link: replay.with(.time(t)), course: graphTheory)) }
        #expect(navigator.current.link == replay.with(.time(60)))
        #expect(navigator.backList.count == 1)
    }

    @Test func aLinkFromOutsideOpensInANewTabUnlessTheWindowWasMadeForIt() {
        let fresh = Navigator()
        #expect(fresh.outsidePlacement(windowAge: 0.3) == .here)
        // The same Today, but a window the user has had open for a while: what it shows stays.
        #expect(fresh.outsidePlacement(windowAge: Navigator.freshWindow + 1) == .tab)
        let moved = Navigator()
        moved.go(Navigator.Entry(link: .place(.grades)))
        moved.back()
        #expect(moved.outsidePlacement(windowAge: 0.3) == .tab)
        let linked = Navigator(Navigator.Entry(link: .course(graphTheory), course: graphTheory))
        #expect(linked.outsidePlacement(windowAge: 0.3) == .tab)
    }

    @Test func eachSettingsTabIsAStep() {
        let navigator = Navigator()
        navigator.go(Navigator.Entry(link: .settings(.general)))
        navigator.go(Navigator.Entry(link: .settings(.claude)))
        #expect(navigator.screen == .settings)
        navigator.back()
        #expect(navigator.current.link == .settings(.general))
    }

    @Test func aPersonOpensOnThePeoplePage() {
        let navigator = Navigator(Navigator.Entry(link: AppLink(.person, UUID())))
        #expect(navigator.screen == .people)
    }
}

/// Where a link points in the open folder, worked out once when it is opened.
@MainActor
struct WorkspaceLinkTests {
    @Test func findsTheCourseThatHoldsWhatALinkNames() throws {
        let workspace = try fixtureWorkspace()
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))?.made)
        #expect(workspace.entry(for: AppLink(.exam, exam))?.course == graphTheory)
        #expect(workspace.entry(for: .course(graphTheory, page: .units))?.course == graphTheory)
        #expect(workspace.entry(for: .place(.grades)) == Navigator.Entry(link: .place(.grades)))
        // Gone or from another folder: nothing to open.
        #expect(workspace.entry(for: AppLink(.exam, UUID())) == nil)
        #expect(workspace.entry(for: AppLink(.semester, UUID())) == nil)
    }

    @Test func aCardIsFoundInItsUnitsQuiz() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let card = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        workspace.run(QuizCardSave(course: graphTheory, cards: [card]))
        #expect(workspace.entry(for: AppLink(.card, card.id))?.course == graphTheory)
        #expect(workspace.entry(for: AppLink(.card, UUID())) == nil)
    }

    @Test func eachStepHasAName() throws {
        let workspace = try fixtureWorkspace()
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))?.made)
        let title = workspace.title(of: Navigator.Entry(link: AppLink(.exam, exam), course: graphTheory))
        #expect(title.hasSuffix("· 중간고사"))
        #expect(workspace.title(of: Navigator.Entry(link: .place(.today))) == String(localized: .rootNavToday))
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a")
        try ActionContext(gist: try #require(workspace.gist), device: workspace.device).edit(graphTheory) { $0.recordings = [recording] }
        workspace.reload()
        let day = try #require(workspace.course(graphTheory)?.file).day(of: try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == session }), calendar: workspace.calendar)
        let replay = Navigator.Entry(link: AppLink(.recording, recording.id, anchor: .time(90)), course: graphTheory)
        #expect(workspace.title(of: replay).hasSuffix("· " + String(localized: .recordingPageNamed(day))))
        #expect(workspace.entry(for: AppLink(.recording, recording.id))?.course == graphTheory)
        #expect(workspace.title(of: Navigator.Entry(link: .settings(.claude))) == "\(String(localized: .rootNavSettings)) · Claude")
    }

    /// The address wins: a link naming a tab opens it, and only one naming none (the sidebar, ⌘,) takes the last picked.
    @Test func aSettingsLinkWithoutATabOpensTheOneLastPicked() throws {
        let workspace = try fixtureWorkspace()
        // The test host shares the app's defaults: the user's last tab is put back.
        let saved = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: SettingsTab.storageKey) }
        UserDefaults.standard.set(SettingsTab.backup.rawValue, forKey: SettingsTab.storageKey)
        #expect(workspace.entry(for: .place(.settings))?.link == .settings(.backup))
        #expect(workspace.entry(for: .settings(.claude))?.link == .settings(.claude))
    }
}

/// Every course page and settings tab has a link of its own and comes back from it.
struct CoursePageLinkTests {
    @Test func everySectionRoundTripsThroughItsPage() {
        for section in CourseSection.allCases {
            #expect(CourseSection(section.page) == section)
        }
        for tab in SettingsTab.allCases {
            #expect(SettingsTab(tab.page) == tab)
        }
        #expect(Set(SettingsTab.allCases.map(\.page)).count == AppLink.SettingsPage.allCases.count)
    }
}

/// The Claude panel's page opens links as a note does; only its own buttons stay with it.
@MainActor
struct ClaudePanelLinkTests {
    final class Opened {
        var links: [AppLink] = []
        var titles: [String] = []
        var actions: [URL] = []
    }

    func coordinator(_ opened: Opened) -> HTMLView.Coordinator {
        let c = HTMLView.Coordinator()
        c.openLink = OpenLinkAction { link, _, _ in opened.links.append(link) }
        c.openNote = { opened.titles.append($0) }
        c.onAction = { opened.actions.append($0) }
        return c
    }

    @Test func anAnswersLinksOpenWhereANotesWould() throws {
        let opened = Opened()
        let c = coordinator(opened)
        let exam = AppLink(.exam, UUID()), block = AppLink(.note, UUID(), anchor: .block("proof"))
        c.open(exam.url)
        c.open(block.url)
        c.open(try #require(URL(string: "folio://note/%EB%A7%A4%EC%B9%AD%20%EC%A0%95%EB%A6%AC")))
        #expect(opened.links == [exam, block])
        #expect(opened.titles == ["매칭 정리"])
        #expect(opened.actions.isEmpty)
    }

    @Test func theButtonsStayWithThePanel() throws {
        let opened = Opened()
        let c = coordinator(opened)
        let button = try #require(URL(string: "folio://action/copy/\(UUID().uuidString)"))
        c.open(button)
        #expect(opened.actions == [button])
        #expect(opened.links.isEmpty && opened.titles.isEmpty)
    }
}
