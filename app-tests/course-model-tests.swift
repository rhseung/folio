import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct CourseModelTests {
    @Test func followsOnlyLinksIntoItsOwnCourse() throws {
        let model = CourseModel(workspace: try fixtureWorkspace(), courseId: graphTheory)
        model.follow(Navigator.Entry(link: .course(UUID(), page: .units), course: UUID()))
        #expect(model.section == .overview)
        let note = UUID()
        model.follow(Navigator.Entry(link: AppLink(.note, note, anchor: .heading("정리")), course: graphTheory))
        #expect(model.section == .notes && model.openNote == note && model.noteAnchor == .heading("정리"))
        let material = AppLink(.material, UUID(), anchor: .page(3))
        model.follow(Navigator.Entry(link: material, course: graphTheory))
        // The materials page opens the file itself, from the place.
        #expect(model.section == .materials && model.place == material && model.noteAnchor == nil)
    }

    /// Following a link changes the page without reporting a move; the page's own moves are reported once each.
    @Test func reportsItsOwnMovesButNotTheOnesItFollows() throws {
        let model = CourseModel(workspace: try fixtureWorkspace(), courseId: graphTheory)
        let unit = AppLink(.unit, UUID())
        model.follow(Navigator.Entry(link: unit, course: graphTheory))
        #expect(model.place == unit)
        model.section = .grades
        #expect(model.place == .course(graphTheory, page: .grades))
        let note = UUID()
        model.section = .notes
        model.openNote = note
        #expect(model.place == AppLink(.note, note))
        // A heading a link opened at doesn't follow to the next note picked by hand.
        model.follow(Navigator.Entry(link: AppLink(.note, note, anchor: .heading("요약")), course: graphTheory))
        #expect(model.noteAnchor == .heading("요약"))
        model.openNote = UUID()
        #expect(model.noteAnchor == nil)
        model.section = .materials
        let file = AppLink(.material, UUID())
        model.moved(file)
        #expect(model.place == file)
        // The same file at another page is the same place.
        model.moved(file.with(.page(9)))
        #expect(model.place == file)
        model.moved(nil)
        #expect(model.place == .course(graphTheory, page: .materials))
    }

    @Test func noteStateFollowsTheReviewNote() throws {
        let workspace = try fixtureWorkspace()
        let model = CourseModel(workspace: workspace, courseId: graphTheory)
        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: past))?.made)
        var file = try #require(workspace.course(graphTheory)).file
        var s = try #require(file.sessions.first { $0.id == id })
        #expect(model.noteState(s, in: file) == "복습 노트 없음")
        #expect(model.weekStatus(s, in: file, now: .now) == "복습 노트 없음")
        s.skipsReview = true
        #expect(model.noteState(s, in: file) == "복습 필요 없음")
        s.isCancelled = true
        #expect(model.weekStatus(s, in: file, now: .now) == "휴강")
        file.course.reviews = false
        s = try #require(file.sessions.first)
        #expect(model.noteState(s, in: file) == "복습 필요 없음")
    }

    @Test func eachStatOpensThePageItSumsUp() throws {
        let workspace = try fixtureWorkspace()
        let model = CourseModel(workspace: workspace, courseId: graphTheory)
        let items = model.stats(try #require(workspace.course(graphTheory)).file, reviews: [], suggested: nil, now: .now)
        #expect(items.map(\.title) == ["다음 수업", "다음 시험", "오늘 복습", "가까운 마감"])
        items[2].action?()
        #expect(model.section == .units)
    }

    @Test func trailingShowsTheSessionCountOnlyOnceThereAreSessions() throws {
        let workspace = try fixtureWorkspace()
        let model = CourseModel(workspace: workspace, courseId: graphTheory)
        #expect(model.trailing(.classes, file: try #require(workspace.course(graphTheory)).file) == nil)
        workspace.run(SessionAdd(course: graphTheory, date: .now))
        #expect(model.trailing(.classes, file: try #require(workspace.course(graphTheory)).file)?.text == "1회")
        #expect(CourseSection.quizStats.title == "오답과 통계" && CourseTab.assessment.title == "평가")
    }
}
