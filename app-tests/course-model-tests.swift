import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct CourseModelTests {
    @Test func followsOnlyItsOwnCourseAndLeavesMaterialTargetsForTheMaterialsPage() throws {
        let model = CourseModel(workspace: try fixtureWorkspace(), courseId: graphTheory)
        #expect(!model.follow(SearchTarget(courseId: UUID(), section: .units)))
        #expect(model.section == .overview)
        let note = UUID()
        #expect(model.follow(SearchTarget(courseId: graphTheory, section: .notes, noteId: note)))
        #expect(model.section == .notes && model.openNote == note)
        #expect(!model.follow(SearchTarget(courseId: graphTheory, section: .materials, materialId: UUID())))
        #expect(model.section == .materials)
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
