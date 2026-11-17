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

    @Test func aReceivedAssignmentShowsItsLMSLinkAndWhenItWasSubmitted() async throws {
        let workspace = try fixtureWorkspace()
        let now = workspace.now
        let room = LMSClassroom(id: 1, title: "그래프 이론[01]")
        let due = now - 86_400
        let sent = due - 3_600
        var snapshot = LMSSnapshot(
            at: now, classrooms: [room], assignments: [LMSAssignment(id: 12, classroom: 1, title: "HW 12", due: due)])
        let logins = MemoryLogins(LMSCredentials(username: "20260000", password: "x"))
        workspace.lms = LMSConnection(source: FixedLMS(snapshot: snapshot), logins: logins)
        await workspace.syncLMS()
        workspace.run(LMSAccept(course: graphTheory, items: [LMSAcceptItem(key: "assignment:12", classroom: 1, title: "HW 12", due: due)]))
        let course = try #require(workspace.course(graphTheory))
        let unsent = try #require(course.file.assignments.first { $0.lmsId == 12 })

        let sheet = AssignmentSheetModel(workspace: workspace, course: course, assignment: unsent)
        let link = try #require(sheet.lms)
        #expect(link.title == "HW 12" && link.classroom == "그래프 이론[01]" && link.url == snapshot.assignments[0].url)
        #expect(link.submitted == false && link.due?.hasPrefix("LMS 마감") == true)
        #expect(AssignmentsModel(workspace: workspace, course: course).row(unsent).lms)

        // LMS에서 내면 동기화가 제출함으로 바꾸고, 목록은 제출본 수 대신 낸 시각을, 시트는 LMS 제출됨을 보인다.
        snapshot.assignments[0].submitted = true
        snapshot.assignments[0].submittedAt = sent
        workspace.lms = LMSConnection(source: FixedLMS(snapshot: snapshot), logins: logins)
        await workspace.syncLMS()
        let updated = try #require(workspace.course(graphTheory))
        let done = try #require(updated.file.assignments.first { $0.id == unsent.id })
        // 파일에 쓰는 날짜는 초 아래를 버린다.
        let at = try #require(done.submittedAt)
        #expect(done.status == .submitted && abs(at.timeIntervalSince(sent)) < 1)
        let on = CourseFile.deadline(at, calendar: workspace.calendar)
        #expect(AssignmentsModel(workspace: workspace, course: updated).row(done).submittedOn == "\(on) 냄")
        let after = try #require(AssignmentSheetModel(workspace: workspace, course: updated, assignment: done).lms)
        #expect(after.submitted == true && after.detail?.contains(" 냄 · ") == true)

        // LMS에서 받지 않은 과제에는 LMS 칸이 없다.
        let own = try #require(workspace.run(AssignmentAdd(course: graphTheory, title: "HW 13"))?.made)
        let plain = try #require(workspace.course(graphTheory)?.file.assignments.first { $0.id == own })
        #expect(AssignmentSheetModel(workspace: workspace, course: updated, assignment: plain).lms == nil)
        #expect(!AssignmentsModel(workspace: workspace, course: updated).row(plain).lms)
    }
}
