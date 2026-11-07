import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

@MainActor
struct SessionMenuModelTests {
    /// A class the timetable holds weeks ahead of the semester's start, not saved yet.
    func planned(_ workspace: Workspace) throws -> Workspace.SuggestedSession {
        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 2, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)])]))
        let course = try #require(workspace.course(graphTheory))
        let semester = try #require(workspace.semester(of: course.file.course))
        let now = try #require(semester.start?.date(in: workspace.calendar)).addingTimeInterval(7 * 86_400)
        return try #require(workspace.plannedSessions(for: course, now: now).dropFirst().first)
    }

    func file(_ workspace: Workspace) throws -> CourseFile { try #require(workspace.course(graphTheory)).file }

    @Test func markingAPlannedClassAbsentSavesTheSessionWithIt() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let item = try planned(workspace)
        #expect(model.canMark(item, .absent))
        let s = try #require(model.make(item, attendance: .absent))
        #expect(s.date == item.suggestion.date && s.week == item.draft.week)
        #expect(model.attendance(of: s) == .absent)
        #expect(try file(workspace).attendance.filter { $0.sessionId == s.id }.count == 1)
    }

    @Test func aPlannedClassesRoughNoteMakesTheSessionFirst() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let item = try planned(workspace)
        let note = try #require(model.roughNote(item))
        let s = try #require(try file(workspace).sessions.first { $0.date == item.suggestion.date })
        #expect(s.roughNoteId == note)
        #expect(model.noteLabel(.rough, of: s) == String(localized: .sessionsOpenRoughNote))
        #expect(model.noteLabel(.review, of: s) == String(localized: .sessionsMakeReviewNote))
    }

    /// The items every screen shows: the review note can be finished and reopened, the class cancelled, its units set.
    @Test func aSavedSessionsItemsChangeIt() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-86_400)))?.made)
        func session() throws -> Session { try #require(model.session(id)) }

        _ = try #require(model.note(.review, of: try session()))
        #expect(try session().reviewNoteUnfinished)
        model.setReviewNoteUnfinished(false, of: try session())
        #expect(try !session().reviewNoteUnfinished)
        model.setReviewNoteUnfinished(true, of: try session())
        #expect(try session().reviewNoteUnfinished)

        model.setSkipsReview(true, of: try session())
        #expect(try session().skipsReview)

        model.setAttendance(.late, of: try session())
        #expect(model.attendance(of: try session()) == .late)
        // A 휴강 has no attendance to count, and takes none.
        model.setKind(.cancelled, of: try session())
        #expect(try session().isCancelled && model.attendance(of: try session()) == .present)
        #expect(!model.takesAttendance(try session()))
        #expect(model.link(of: try session()) == nil)

        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        model.toggleUnit(unit, of: try session())
        #expect(try session().unitIds == [unit])
        model.toggleUnit(unit, of: try session())
        #expect(try session().unitIds.isEmpty)
    }

    /// A makeup that was cancelled goes back to a makeup, not to a lecture.
    @Test func theMenuPicksAnyKind() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-86_400), kind: .makeup))?.made)
        func session() throws -> Session { try #require(model.session(id)) }
        #expect(model.kindOptions.map(\.0) == [.lecture, .cancelled, .makeup])

        model.setAttendance(.late, of: try session())
        model.setKind(.cancelled, of: try session())
        #expect(try session().kind == .cancelled && model.attendance(of: try session()) == .present)
        model.setKind(.makeup, of: try session())
        #expect(try session().kind == .makeup)
        #expect(model.takesAttendance(try session()))
        model.setKind(.lecture, of: try session())
        #expect(try session().kind == .lecture)
    }

    /// One skip for every screen: the review screen's keeps the time the unit was open, a list's has none.
    @Test func skippingFromTheReviewScreenKeepsTheTimeOpen() throws {
        let workspace = try fixtureWorkspace()
        let a = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let b = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        let review = ReviewModel(workspace: workspace, items: [.init(courseId: graphTheory, unitId: a)])
        review.started = .now.addingTimeInterval(-120)
        review.record(.skip)
        _ = workspace.skipReviews([(graphTheory, b)])

        let events = workspace.reviews(of: graphTheory).map(\.event)
        #expect(events.map(\.result) == [.skip, .skip])
        #expect(events.first { $0.unitId == a }.map { $0.seconds >= 120 } == true)
        #expect(events.first { $0.unitId == b }?.seconds == 0)
        let log = try #require(workspace.course(graphTheory)).store.log
        #expect(try log.readAll().events(StudySessionEvent.self).map(\.event.screen) == ["review"])
    }
}
