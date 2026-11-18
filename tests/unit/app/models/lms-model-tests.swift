import FolioActions
import FolioDomain
import FolioLMS
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct LMSModelTests {

    func workspace(_ items: (Date) -> LMSSnapshot) throws -> Workspace {
        let workspace = try fixtureWorkspace()
        workspace.lms = LMSConnection(
            source: FixedLMS(snapshot: items(workspace.now)),
            logins: MemoryLogins(LMSCredentials(username: "20260000", password: "x")))
        return workspace
    }

    static func snapshot(_ now: Date) -> LMSSnapshot {
        LMSSnapshot(
            at: now, classrooms: [LMSClassroom(id: 1, title: "그래프 이론[01]"), LMSClassroom(id: 2, title: "소방 안전 교육")],
            assignments: [LMSAssignment(id: 100, classroom: 1, title: "Homework Set #5", due: now.addingTimeInterval(86_400))],
            files: [LMSFile(id: 200, classroom: 1, title: "Flows", week: "7주차")],
            notices: [LMSNotice(id: 300, board: 9, classroom: 2, title: "교육 일정 안내")])
    }

    func proposals(_ model: LMSModel) -> [Proposal] { model.board.rooms.flatMap(\.proposals) }

    @Test func firstSyncMarksWhatClassroomsHoldAndProposesOpenAssignments() async throws {
        let workspace = try workspace(Self.snapshot)
        let model = LMSModel(workspace: workspace)
        #expect(model.board.rooms.isEmpty)

        await workspace.syncLMS()
        #expect(workspace.settings.lms.known == [1, 2])
        #expect(proposals(model).map(\.id) == ["lms/assignment:100"])
        #expect(model.board.rooms.map(\.id) == [1, 2])
        #expect(model.board.rooms.map { $0.hidden.map(\.id) } == [["file:200"], ["notice:300"]])
        #expect(model.board.count == 1)
        #expect(model.todayRows.map(\.classroom.title) == ["그래프 이론[01]"])
        #expect(model.earliestDue?.contains("Homework Set #5") == true)
    }

    @Test func assignmentRowsNameTheirAttachments() async throws {
        let one = [LMSAttachment(name: "slow_problem_2.pdf", path: "/a")]
        let workspace = try workspace { now in
            LMSSnapshot(
                at: now, classrooms: [LMSClassroom(id: 1, title: "그래프 이론[01]")],
                assignments: [
                    LMSAssignment(id: 100, classroom: 1, title: "Slow Problem #2", attachments: one),
                    LMSAssignment(id: 101, classroom: 1, title: "HW6", attachments: one + [LMSAttachment(name: "b.pdf", path: "/b")]),
                    LMSAssignment(id: 102, classroom: 1, title: "HW7"),
                ])
        }
        await workspace.syncLMS()
        let model = LMSModel(workspace: workspace)
        // 강의실 페이지에서는 첨부만, 전체에서는 받을 과목이 없어 강의실 이름을 앞에 붙인다. 종류는 아이콘이 말한다.
        let details = proposals(model).map { model.detail($0, source: false) }
        #expect(details[0] == "slow_problem_2.pdf")
        #expect(details[1]?.contains("slow_problem_2.pdf") == true && details[1]?.contains("1") == true)
        #expect(details[2] == nil)
        #expect(model.detail(proposals(model)[0], source: true) == "그래프 이론[01] · slow_problem_2.pdf")

        // 내려받지 못한 첨부(뷰어 전용)는 건너뛰고 과제는 받는다.
        await model.add([proposals(model)[0]], into: graphTheory)
        #expect(workspace.course(graphTheory)?.file.assignments.contains { $0.lmsId == 100 } == true)
    }

    @Test func eachProposalGoesToTheCoursePickedAndDismissingHidesIt() async throws {
        let workspace = try workspace(Self.snapshot)
        await workspace.syncLMS()
        workspace.run(LMSMark(keys: ["file:200", "notice:300"], handled: false))
        let model = LMSModel(workspace: workspace)
        #expect(model.board.rooms.map(\.id) == [1, 2])
        let all = proposals(model)
        #expect(all.map(\.id) == ["lms/assignment:100", "lms/file:200", "lms/notice:300"])
        #expect(all.map(\.canApprove) == [true, true, false])
        #expect(model.addable(all).count == 2)
        #expect(model.targets.contains { $0.id == graphTheory })

        await model.add([all[0]], into: graphTheory)
        #expect(workspace.course(graphTheory)?.file.assignments.filter { $0.lmsId == 100 }.count == 1)
        model.dismiss([all[2]])
        await model.add([all[1]], into: graphTheory)
        // 받으려 해 보니 뷰어 전용이라 받지 못한 자료는 남고, 이제 받을 수 없다고 표시된다.
        #expect(proposals(model).map(\.id) == ["lms/file:200"])
        let left = try #require(proposals(model).first)
        #expect(!left.canApprove && left.flag == .viewerOnly)
        #expect(model.detail(left, source: false) == ProposalFlag.viewerOnly.label)

        let hidden = model.board.rooms.flatMap(\.hidden)
        let added = try #require(hidden.first { $0.id == "assignment:100" })
        #expect(!added.proposable && model.detail(added).contains("그래프 이론"))
        let notice = try #require(hidden.first { $0.id == "notice:300" })
        #expect(notice.proposable)
        model.proposeAgain(notice)
        #expect(proposals(model).map(\.id) == ["lms/file:200", "lms/notice:300"])
    }

    @Test func roomsAreRowsOfTheTabAndFollowTheAddress() async throws {
        let workspace = try workspace(Self.snapshot)
        await workspace.syncLMS()
        let model = LMSModel(workspace: workspace)
        guard case .all(let sections) = model.shown(in: model.board) else { Issue.record("not everything"); return }
        #expect(sections.map(\.id) == ["new", "deadlines"])
        model.follow(.lms(.classroom(1)))
        guard case .room(let room) = model.shown(in: model.board) else { Issue.record("not the room"); return }
        #expect(model.title(of: .room(room)) == "그래프 이론[01]")
        model.follow(.lms(.classroom(99)))
        guard case .gone = model.shown(in: model.board) else { Issue.record("a room that is not there"); return }
        model.follow(.place(.today))
        guard case .gone = model.shown(in: model.board) else { Issue.record("another place changed the row"); return }
    }

    @Test func receivingRemembersTheRoomsCourseForTheNextTime() async throws {
        let workspace = try workspace { now in
            var s = Self.snapshot(now)
            s.assignments.append(LMSAssignment(id: 101, classroom: 1, title: "HW6", due: now.addingTimeInterval(9 * 86_400)))
            return s
        }
        await workspace.syncLMS()
        let model = LMSModel(workspace: workspace)
        #expect(model.remembered.isEmpty && model.remembered(1) == nil)
        await model.add([proposals(model)[0]], into: graphTheory)
        #expect(workspace.settings.lms.course(of: 1) == graphTheory)
        #expect(model.remembered(1)?.id == graphTheory)
        #expect(workspace.lmsRooms(of: graphTheory).map(\.classroom.id) == [1])
        // 과목을 기억한 강의실의 행은 전체에서 강의실 대신 그 과목 이름을 앞에 붙인다.
        let title = try #require(workspace.course(graphTheory)?.title)
        #expect(model.detail(proposals(model)[0], source: true)?.hasPrefix(title) == true)
        #expect(model.memoryLabel(try #require(model.board.room(1))) == workspace.course(graphTheory)?.title)

        #expect(model.remembered.map(\.id) == ["lms/assignment:101"])
        await model.addRemembered()
        #expect(workspace.course(graphTheory)?.file.assignments.contains { $0.lmsId == 101 } == true)

        model.rememberNoCourse(1)
        #expect(workspace.settings.lms.room(1) == LMSRoom() && model.remembered(1) == nil)
        model.forget(1)
        #expect(workspace.settings.lms.room(1) == nil)
    }

    @Test func whatDiffersFromTheLMSIsFixedOneByOne() async throws {
        let workspace = try workspace(Self.snapshot)
        await workspace.syncLMS()
        let model = LMSModel(workspace: workspace)
        await model.add([proposals(model)[0]], into: graphTheory)
        #expect(proposals(model).isEmpty)

        // 그 뒤 LMS에서 과제를 내고 마감이 미뤄졌다. 낸 것은 묻지 않고 제출함으로 바꾸고, 마감은 묻는다.
        let later = workspace.now.addingTimeInterval(3 * 86_400)
        var changed = Self.snapshot(workspace.now)
        changed.assignments = [LMSAssignment(id: 100, classroom: 1, title: "Homework Set #5", due: later, submitted: true)]
        workspace.lms = LMSConnection(
            source: FixedLMS(snapshot: changed), logins: MemoryLogins(LMSCredentials(username: "20260000", password: "x")))
        await workspace.syncLMS()
        let assignment = { workspace.course(graphTheory)?.file.assignments.first { $0.lmsId == 100 } }
        #expect(assignment()?.status == .submitted)
        #expect(workspace.settings.lms.handled.map(\.description).contains("submitted:100"))
        let fixes = proposals(model)
        #expect(fixes.map(\.kind) == [.lmsDue])
        #expect(fixes.map { model.fixLabel($0) } == ["반영"])
        guard case .all(let sections) = model.shown(in: model.board) else { Issue.record("not everything"); return }
        #expect(sections.first?.id == "differs")

        // 사용자가 할 일로 되돌리면 다음 동기화가 다시 바꾸지 않는다.
        workspace.run(AssignmentStatusSet(course: graphTheory, assignment: try #require(assignment()).id, status: .todo))
        await workspace.syncLMS()
        #expect(assignment()?.status == .todo)
        model.dismiss(proposals(model))
        #expect(proposals(model).isEmpty)
        #expect(assignment()?.due != later)
    }
}
