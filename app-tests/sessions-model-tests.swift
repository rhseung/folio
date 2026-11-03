import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct SessionsModelTests {
    func session(_ workspace: Workspace, daysFromNow days: Int) throws -> Session {
        let date = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: date))?.made)
        return try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == id })
    }

    @Test func subtitleCountsMissingNotesAndUnitsOnlyOnceUnitsExist() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file) == "회차가 아직 없습니다")
        _ = try session(workspace, daysFromNow: -2)
        _ = try session(workspace, daysFromNow: 3)
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file) == "회차 2개 · 복습 노트 없음 1")
        workspace.run(UnitAdd(course: graphTheory, title: "매칭"))
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file) == "회차 2개 · 복습 노트 없음 1 · 단원 없음 1")
    }

    @Test func aClassWithNoEndOffersJoinUntilTheEndTheFormShows() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(CourseSet(course: graphTheory, [.schedule([])]))
        // 10:30 of the study day, whatever the clock says: late at night the form's end stops at the day's end, which
        // the button doesn't, and before the day boundary the calendar's today is not the study day.
        let day = try #require(workspace.today.date(in: Calendar.current))
        let start = try #require(Calendar.current.date(byAdding: .minute, value: 10 * 60 + 30, to: day))
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: start, link: "https://zoom.us/j/1"))?.made)
        let s = try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == id })
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        func file() throws -> CourseFile { try #require(workspace.course(graphTheory)).file }
        func formEnd() -> Date { SessionFormModel(workspace: workspace, courseId: graphTheory, session: s).end }

        #expect(formEnd() == start.addingTimeInterval(TimeInterval(workspace.settings.classMinutes * 60)))
        #expect(model.offersJoin(s, in: try file(), now: formEnd().addingTimeInterval(-60)))
        #expect(!model.offersJoin(s, in: try file(), now: formEnd()))

        // Off the timetable of a course whose classes run two hours: two hours, in the form and for the button.
        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 15 * 60)])]))
        #expect(formEnd() == start.addingTimeInterval(2 * 3600))
        #expect(model.offersJoin(s, in: try file(), now: formEnd().addingTimeInterval(-60)))
        #expect(!model.offersJoin(s, in: try file(), now: formEnd()))
    }

    @Test func timelineRailsStopAtTheEndsAndColorUpToNow() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        _ = try session(workspace, daysFromNow: -14)
        _ = try session(workspace, daysFromNow: 14)
        let rows = model.timeline(try #require(workspace.course(graphTheory)).file)
        #expect(rows.first?.first == true && rows.first?.above == nil)
        #expect(rows.last?.below == nil)
        // The past session's line is held, the future one's isn't.
        let sessions = rows.filter { if case .session = $0.item { true } else { false } }
        #expect(sessions.map(\.above) == [true, false])
    }

    /// A 휴강 weeks ahead: the class shows on the timeline before it is a session, and marking it saves one.
    @Test func plannedClassesRunToTheTermsEndAndCancellingOneSavesIt() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 2, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)])]))
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let course = try #require(workspace.course(graphTheory))
        let semester = try #require(workspace.semester(of: course.file.course))
        let end = try #require(semester.end?.date(in: workspace.calendar))
        // Mid-term, on the semester's own dates rather than the clock, so the plan has weeks left to show.
        let now = try #require(semester.start?.date(in: workspace.calendar)).addingTimeInterval(7 * 7 * 86_400)
        func planned() throws -> [Workspace.SuggestedSession] { model.timeline(try #require(workspace.course(graphTheory)).file, now: now).compactMap(\.planned) }

        let plan = try planned()
        #expect(plan.count >= 2 && plan.allSatisfy { $0.suggestion.date > now && $0.suggestion.date <= end })
        #expect(plan.allSatisfy { workspace.calendar.isoWeekday(of: $0.suggestion.date) == 2 })

        let second = plan[1]
        SuggestedSessionItems.make(second, workspace, cancelled: true)
        let saved = try #require(workspace.course(graphTheory)?.file.sessions.first { $0.date == second.suggestion.date })
        #expect(saved.isCancelled && saved.week == second.draft.week)
        #expect(try planned().map(\.suggestion.date) == plan.map(\.suggestion.date).filter { $0 != second.suggestion.date })
    }

    @Test func titleFallsBackFromTopicToUnitsToName() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let s = try session(workspace, daysFromNow: -1)
        #expect(model.title(of: s, in: try #require(workspace.course(graphTheory)).file) == workspace.course(graphTheory)?.file.name(of: s))
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [s.id]))
        #expect(model.title(of: s, in: try #require(workspace.course(graphTheory)).file) == "매칭")
        var topic = try #require(workspace.course(graphTheory)?.file.sessions.first)
        topic.topic = "매칭 이론"
        #expect(model.title(of: topic, in: try #require(workspace.course(graphTheory)).file) == "매칭 이론")
        #expect(model.unitsInTitle(topic, in: try #require(workspace.course(graphTheory)).file))
    }

    @Test func aheadSaysTodayTomorrowOrHowManyDays() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let later = { (days: Int) in calendar.date(byAdding: .day, value: days, to: now)! }
        #expect(SessionsModel.ahead(later(0), clock: "13:00", now: now, calendar: calendar) == "오늘 13:00")
        #expect(SessionsModel.ahead(later(1), clock: "13:00", now: now, calendar: calendar) == "내일 13:00")
        #expect(SessionsModel.ahead(later(5), clock: "13:00", now: now, calendar: calendar) == "5일 후")
    }

    @Test func untouchedFutureSessionsAreListedAndRemovedTogether() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        _ = try session(workspace, daysFromNow: 7)
        _ = try session(workspace, daysFromNow: -7)
        model.loadUntouched(try #require(workspace.course(graphTheory)))
        #expect(model.untouched.count == 1 && model.untouchedMore == 0)
        model.removeUntouched()
        #expect(workspace.course(graphTheory)?.file.sessions.count == 1)
    }
}
