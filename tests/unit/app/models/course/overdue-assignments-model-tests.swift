import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct OverdueAssignmentsModelTests {
    @Test func rowsShowTheCeilingAndTheButtonsSettleThem() throws {
        let workspace = try fixtureWorkspace()
        let now = workspace.now
        workspace.run(PolicySet(course: graphTheory, lateRule: .set(LateRule(percentPerDay: 10, days: 3))))
        let late = try #require(workspace.run(AssignmentAdd(course: graphTheory, title: "HW 9", due: now - 3_600))?.made)
        let lost = try #require(workspace.run(AssignmentAdd(course: graphTheory, title: "HW 8", due: now - 5 * 86_400))?.made)
        let model = OverdueAssignmentsModel(workspace: workspace, course: graphTheory)

        let rows = model.rows(now: now)
        #expect(rows.map(\.id).filter { [late, lost].contains($0) } == [lost, late])
        let row = try #require(rows.first { $0.id == late })
        #expect(row.ceiling?.contains("90") == true && !row.lost)
        #expect(try #require(rows.first { $0.id == lost }).lost)

        model.submit(row)
        model.miss(try #require(rows.first { $0.id == lost }))
        #expect(!model.rows(now: now).contains { [late, lost].contains($0.id) })
        let file = try #require(workspace.course(graphTheory)?.file)
        #expect(file.assignments.first { $0.id == late }?.submittedAt != nil)
        #expect(file.assignments.first { $0.id == lost }?.status == .missed)
    }
}
