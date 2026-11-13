import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct UnitsModelTests {
    func file(_ workspace: Workspace) throws -> CourseFile { try #require(workspace.course(graphTheory)).file }

    @Test func addClearsTheFieldAndRemoveClosesTheOpenUnit() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        #expect(!model.canAdd)
        model.newTitle = "매칭"
        model.add()
        #expect(model.newTitle.isEmpty)
        let unit = try #require(try file(workspace).units.first)
        #expect(unit.title == "매칭")

        model.openUnit = unit.id
        model.remove(unit)
        let pending = try #require(model.pending)
        // The declaration's words, so the screen follows when the action's wording changes.
        #expect(pending.question == workspace.confirmation(UnitRemove(course: graphTheory, unit: unit.id)) && pending.question.contains("'매칭'"))
        #expect(pending.refusal == nil)
        #expect(try file(workspace).units.count == 1)
        pending.perform()
        #expect(try file(workspace).units.isEmpty && model.openUnit == nil)
    }

    @Test func sessionsLineNamesThreeThenCountsTheRest() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        #expect(model.sessionsLine(try #require(try file(workspace).units.first), in: try file(workspace)) == "회차 없음")
        let ids = try (1...4).map { day in
            try #require(workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -day * 7, to: .now)!))?.made)
        }
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: ids))
        let f = try file(workspace)
        let unit = try #require(f.units.first)
        let names = model.sessions(of: unit, in: f).map { f.day(of: $0, calendar: workspace.calendar) }
        #expect(model.sessionsLine(unit, in: f) == "\(names.prefix(3).joined(separator: ", ")) 외 1")
        #expect(model.detail(unit, state: nil, in: f) == model.sessionsLine(unit, in: f))
    }

    @Test func linkMenuLeavesOutCancelledClassesUnlessLinked() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let day = { (d: Int) in Calendar.current.date(byAdding: .day, value: -d, to: .now)! }
        let held = try #require(workspace.run(SessionAdd(course: graphTheory, date: day(2)))?.made)
        let cancelled = try #require(workspace.run(SessionAdd(course: graphTheory, date: day(1), kind: .cancelled))?.made)
        func menu() throws -> [UUID] { model.linkMenu(try #require(try file(workspace).units.first), in: try file(workspace)).map(\.id) }
        #expect(try menu() == [held])
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [cancelled]))
        #expect(try menu() == [cancelled, held])
    }

    @Test func subtitleCountsUnitsDueAndUnlinkedClasses() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        workspace.run(UnitAdd(course: graphTheory, title: "매칭"))
        workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))
        #expect(model.subtitle(try file(workspace), states: [:]) == "단원 1개 · 오늘 복습 0개 · 단원 없는 회차 1")
    }

    /// A class note shows under a unit while its class is linked to the unit, and leaves with the class.
    @Test func aClassNoteLeavesTheUnitWithItsClass() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unitId = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [session]))
        let note = try #require(workspace.run(SessionNote(course: graphTheory, session: session, kind: .review))?.made)
        model.loadNotes(try #require(try file(workspace).units.first))
        #expect(model.notes.map(\.meta.id) == [note])

        workspace.run(UnitLink(course: graphTheory, unit: unitId, sessions: [session], linked: false))
        model.loadNotes(try #require(try file(workspace).units.first))
        #expect(model.notes.isEmpty)
    }

    @Test func reviewTimeReadsInSecondsThenMinutes() {
        #expect(UnitsModel.minutes(42) == "42초")
        #expect(UnitsModel.minutes(150) == "2분")
    }
}
