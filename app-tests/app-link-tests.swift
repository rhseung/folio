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
    }
}

/// Every course page has a link of its own and comes back from it.
struct CoursePageLinkTests {
    @Test func everySectionRoundTripsThroughItsPage() {
        for section in CourseSection.allCases {
            #expect(CourseSection(section.page) == section)
        }
    }
}
