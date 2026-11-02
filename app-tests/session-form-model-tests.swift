import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct SessionFormModelTests {
    func file(_ workspace: Workspace) throws -> CourseFile { try #require(workspace.course(graphTheory)).file }

    @Test func addingAMakeupKeepsItsEndTopicAndLink() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionFormModel(workspace: workspace, courseId: graphTheory)
        let start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: workspace.now.addingTimeInterval(86_400))!
        model.setStart(start)
        model.setEnd(22 * 60 + 15)
        model.topic = "보강"
        model.link = " https://us06web.zoom.us/j/88470108867?pwd=abc.1 "
        #expect(!model.disabled && model.note == nil)
        model.submit()

        let s = try #require(try file(workspace).sessions.first { $0.date == start })
        #expect(s.topic == "보강")
        #expect(s.end == start.addingTimeInterval(75 * 60))
        #expect(s.link == "https://us06web.zoom.us/j/88470108867?pwd=abc.1")
        #expect(SessionsModel(workspace: workspace, courseId: graphTheory).link(of: s, in: try file(workspace)) != nil)
    }

    @Test func aMeetingIDOrAnEarlyEndCannotBeSaved() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionFormModel(workspace: workspace, courseId: graphTheory)
        // The form says what the save rules say, not a copy of them.
        model.link = "884 7010 8867"
        #expect(model.disabled && model.note?.contains("참가 링크") == true)
        model.link = ""
        model.setEnd(17 * 60)
        #expect(model.disabled && model.note?.contains("끝 시각") == true)
    }

    @Test func aClassMovedToAnotherSlotEndsWithThatSlotAndOffTheTimetableKeepsItsLength() throws {
        let workspace = try fixtureWorkspace()
        let calendar = workspace.calendar
        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 14 * 60 + 15),
                                                                ClassTime(weekday: 3, startMinute: 13 * 60, endMinute: 15 * 60)])]))
        let monday = calendar.date(byAdding: .hour, value: 13, to: calendar.startOfWeek(containing: workspace.now))!
        let wednesday = monday.addingTimeInterval(2 * 86_400)

        func moved(to date: Date) throws -> Session {
            let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: monday))?.made)
            let session = try #require(try file(workspace).sessions.first { $0.id == id })
            #expect(session.end == nil)
            let model = SessionFormModel(workspace: workspace, courseId: graphTheory, session: session)
            model.setStart(date)
            #expect(model.note == nil || model.note == String(localized: .sessionsRenameOnMove))
            model.submit()
            return try #require(try file(workspace).sessions.first { $0.id == id })
        }

        // Onto Wednesday's longer slot: still the slot's end, so changing Wednesday's times later moves it.
        let onSlot = try moved(to: wednesday)
        #expect(onSlot.end == nil)
        #expect(onSlot.end(schedule: try file(workspace).course.schedule, calendar: calendar) == wednesday.addingTimeInterval(2 * 3600))

        // Off the timetable it keeps its 75 minutes.
        let evening = wednesday.addingTimeInterval(6 * 3600)
        #expect(try moved(to: evening).end == evening.addingTimeInterval(75 * 60))

        // A makeup with an end of its own, moved onto Wednesday's slot: what the form showed is what's saved.
        let makeupId = try #require(workspace.run(SessionAdd(course: graphTheory, date: monday.addingTimeInterval(8 * 3600),
                                                             end: monday.addingTimeInterval(8 * 3600 + 75 * 60)))?.made)
        let makeup = try #require(try file(workspace).sessions.first { $0.id == makeupId })
        let model = SessionFormModel(workspace: workspace, courseId: graphTheory, session: makeup)
        model.setStart(wednesday)
        #expect(model.end == wednesday.addingTimeInterval(2 * 3600))
        model.submit()
        let saved = try #require(try file(workspace).sessions.first { $0.id == makeupId })
        #expect(saved.end == nil)
        #expect(saved.end(schedule: try file(workspace).course.schedule, calendar: calendar) == model.end)
    }

    @Test func editingChangesOnlyWhatChanged() throws {
        let workspace = try fixtureWorkspace()
        let start = Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: workspace.now)!
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: start, link: "https://zoom.us/j/1"))?.made)
        let before = try #require(try file(workspace).sessions.first { $0.id == id })

        let model = SessionFormModel(workspace: workspace, courseId: graphTheory, session: before)
        #expect(model.title.hasSuffix("편집"))
        model.topic = "매칭"
        model.link = ""
        model.submit()
        let after = try #require(try file(workspace).sessions.first { $0.id == id })
        #expect(after.topic == "매칭" && after.link == nil)
        #expect(after.date == before.date && after.end == before.end && after.week == before.week)
    }

    @Test func aDateOnlySessionGetsNoEndUnlessOneIsPicked() throws {
        let workspace = try fixtureWorkspace()
        let midnight = Calendar.current.startOfDay(for: workspace.now)
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: midnight))?.made)
        let session = try #require(try file(workspace).sessions.first { $0.id == id })
        #expect(session.end == nil)
        let model = SessionFormModel(workspace: workspace, courseId: graphTheory, session: session)
        model.topic = "그래프"
        model.submit()
        #expect(try file(workspace).sessions.first { $0.id == id }?.end == nil)
    }

    @Test func movingToAnotherWeekWarnsTheNameChanges() throws {
        let workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now))?.made)
        let session = try #require(try file(workspace).sessions.first { $0.id == id })
        let model = SessionFormModel(workspace: workspace, courseId: graphTheory, session: session)
        model.setStart(session.date.addingTimeInterval(14 * 86_400))
        #expect(model.note == String(localized: .sessionsRenameOnMove))
    }
}
