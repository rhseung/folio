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
        model.link = "884 7010 8867"
        #expect(model.disabled && model.note == String(localized: .sessionsLinkInvalid))
        model.link = ""
        model.setEnd(17 * 60)
        #expect(model.disabled && model.note == String(localized: .sessionsEndBeforeStart))
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
