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
        model.removing = unit
        #expect(model.removalTitle == "‘매칭’ 단원을 삭제할까요?")
        model.remove(unit)
        #expect(try file(workspace).units.isEmpty && model.openUnit == nil && model.removing == nil)
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
        let names = model.sessions(of: unit, in: f).map { f.name(of: $0) }
        #expect(model.sessionsLine(unit, in: f) == "\(names.prefix(3).joined(separator: ", ")) 외 1")
        #expect(model.detail(unit, state: nil, in: f) == model.sessionsLine(unit, in: f))
    }

    @Test func subtitleCountsUnitsDueAndUnlinkedClasses() throws {
        let workspace = try fixtureWorkspace()
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        workspace.run(UnitAdd(course: graphTheory, title: "매칭"))
        workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))
        #expect(model.subtitle(try file(workspace), states: [:]) == "단원 1개 · 오늘 복습 0개 · 단원 없는 회차 1")
    }

    @Test func reviewTimeReadsInSecondsThenMinutes() {
        #expect(UnitsModel.minutes(42) == "42초")
        #expect(UnitsModel.minutes(150) == "2분")
    }
}
