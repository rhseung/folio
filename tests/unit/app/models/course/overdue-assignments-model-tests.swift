import FolioActions
import FolioDomain
import FolioLMS
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

    @Test func receivedAssignmentsNotSubmittedInTheLMSAreFlagged() async throws {
        let workspace = try fixtureWorkspace()
        let now = workspace.now
        let room = LMSClassroom(id: 1, title: "그래프 이론[01]")
        let past = now - 3_600
        let snapshot = LMSSnapshot(
            at: now, classrooms: [room],
            assignments: [
                LMSAssignment(id: 10, classroom: 1, title: "HW 10", due: past),
                LMSAssignment(id: 11, classroom: 1, title: "HW 11", due: past),
            ])
        workspace.lms = LMSConnection(
            source: FixedLMS(snapshot: snapshot), logins: MemoryLogins(LMSCredentials(username: "20260000", password: "x")))
        await workspace.syncLMS()
        let items = [10, 11].map { LMSAcceptItem(key: "assignment:\($0)", classroom: 1, title: "HW \($0)", due: past) }
        workspace.run(LMSAccept(course: graphTheory, items: items))
        let added = { (lms: Int) in workspace.course(graphTheory)?.file.assignments.first { $0.lmsId == lms } }
        let submitted = try #require(added(11)).id
        workspace.run(AssignmentStatusSet(course: graphTheory, assignment: submitted, status: .submitted))

        // 할 일인 과제는 표시만 붙고, Folio에서 제출함인 과제도 LMS에 내지 않았으므로 여기 선다.
        let model = OverdueAssignmentsModel(workspace: workspace)
        let rows = model.rows(now: now).filter { $0.lms != nil }
        #expect(rows.map(\.id) == [try #require(added(10)).id, submitted])
        #expect(rows.map(\.submitted) == [false, true])
        #expect(rows[1].lms == snapshot.assignments[1].url)
    }
}
