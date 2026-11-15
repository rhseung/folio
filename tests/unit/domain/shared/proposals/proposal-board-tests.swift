import FolioDomain
import Foundation
import Testing

struct ProposalBoardTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let course = UUID()

    var room: LMSClassroom { LMSClassroom(id: 1, title: "그래프 이론[01]") }

    func inbox(_ snapshot: LMSSnapshot) -> LMSInbox {
        LMSInbox.build(snapshot, settings: LMSSettings(known: snapshot.classrooms.map(\.id)), courses: [], now: now)
    }

    func items(_ action: ActionProposal?) -> [String] {
        guard case .array(let items)? = action?.input["items"] else { return [] }
        return items.compactMap { if case .string(let k)? = $0["key"] { k } else { nil } }
    }

    func chat(title: String = "대화", updated: Date? = nil, _ proposals: [ActionProposal]) -> Chat {
        var c = Chat(device: device, at: updated ?? now, title: title)
        c.messages = [ChatMessage(role: .assistant, text: "", at: now, proposals: proposals)]
        return c
    }

    @Test func lmsItemsAreReceivedInTheCoursePickedWhenApproved() throws {
        let due = now.addingTimeInterval(86_400)
        let board = ProposalBoard.build(
            lms: inbox(
                LMSSnapshot(
                    at: now, classrooms: [room], assignments: [.init(id: 100, classroom: 1, title: "HW5", due: due)],
                    files: [.init(id: 200, classroom: 1, title: "Flows")], notices: [.init(id: 300, board: 9, classroom: 1, title: "안내")])))
        let proposals = board.rooms[0].proposals
        #expect(proposals.map(\.kind) == [.lmsAssignment, .lmsFile, .lmsNotice])
        #expect(proposals.map(\.canApprove) == [true, true, false])
        #expect(proposals.allSatisfy { $0.canDismiss })
        #expect(proposals[0].due == due)

        // 강의실을 과목에 잇지 않으므로 과목을 고르기 전에는 승인할 수 없다.
        #expect(proposals[0].action(in: nil) == nil)
        let approvals = proposals.approvals(in: course)
        #expect(approvals.count == 1)
        #expect(approvals[0].command == "lms accept")
        #expect(approvals[0].input["course"] == .string(course.uuidString))
        #expect(items(approvals[0]) == ["assignment:100", "file:200"])
        guard case .array(let received)? = approvals[0].input["items"] else { Issue.record("no items"); return }
        #expect(received[0]["title"] == "HW5")

        let dismissals = proposals.dismissals
        #expect(dismissals.count == 1)
        #expect(dismissals[0].command == "lms mark")
        #expect(dismissals[0].input["keys"] == ["assignment:100", "file:200", "notice:300"])
    }

    @Test func viewerOnlyFilesCanOnlyBeOpenedOrDismissed() {
        let board = ProposalBoard.build(
            lms: inbox(LMSSnapshot(at: now, classrooms: [room], files: [.init(id: 200, classroom: 1, title: "Flows")])),
            viewerOnly: [200])
        let p = board.rooms[0].proposals[0]
        #expect(p.flag == .viewerOnly)
        #expect(!p.canApprove)
        #expect([p].approvals(in: course).isEmpty)
    }

    @Test func downloadedFilesGoIntoTheItemThatIsReceived() {
        let p = LMSProposal(item: .assignment(.init(id: 100, classroom: 1, title: "HW5")), classroom: room).proposal()
        let got = p.downloaded(files: ["/tmp/a.pdf"]).action
        #expect(got?.input["items"] == [["key": "assignment:100", "title": "HW5", "files": ["/tmp/a.pdf"]]])
        let file = LMSProposal(item: .file(.init(id: 200, classroom: 1, title: "Flows")), classroom: room).proposal()
        #expect(file.downloaded(file: "/tmp/f.pdf").action?.input["items"] == [["key": "file:200", "file": "/tmp/f.pdf"]])
    }

    @Test func chatsListTheProposalsStillWaiting() throws {
        let open = ActionProposal(id: UUID(), command: "exam add", input: ["title": "중간"])
        let applied = ActionProposal(id: UUID(), command: "exam add", input: ["title": "기말"], applied: true)
        let elsewhere = ActionProposal(id: UUID(), command: "exam add", input: ["title": "모의"])
        let busy = chat(title: "시험 정리", [open, applied, elsewhere]).markingApplied([try #require(elsewhere.id)])
        let pending = busy.pending(course: course, targets: [:])
        #expect(pending.map(\.kind) == [.claude])
        guard case .claude(let source) = pending[0].source else { Issue.record("not a chat proposal"); return }
        #expect(source.proposal == open)
        #expect(source.index == 0)
        #expect(source.course == course)
        #expect(source.chatTitle == "시험 정리")
        // LMS 탭은 Claude 제안을 받지 않는다. 그 대화의 패널에서 승인한다.
        #expect(pending[0].kind.group == nil)
        #expect(!pending[0].canDismiss)
    }

    @Test func aProposalALaterAnswerReplacesIsNotWaiting() {
        var c = Chat(device: device, at: now)
        let target = ProposalTarget(arguments: ["note"], effect: .replaces(covers: []))
        c.messages = [
            ChatMessage(role: .assistant, text: "", at: now, proposals: [ActionProposal(command: "note write", input: ["note": "a.md"])]),
            ChatMessage(role: .assistant, text: "", at: now, proposals: [ActionProposal(command: "note write", input: ["note": "a.md"])]),
        ]
        let pending = c.pending(course: course, targets: ["note write": target])
        #expect(pending.count == 1)
        guard case .claude(let source) = pending[0].source else { return }
        #expect(source.message == c.messages[1].id)
    }

    @Test func everythingGroupsInTheDeclaredOrderAndSkipsEmptyGroups() {
        let snapshot = LMSSnapshot(
            at: now, classrooms: [room, LMSClassroom(id: 2, title: "소방 안전 교육")],
            files: [.init(id: 200, classroom: 1, title: "Flows")], notices: [.init(id: 300, board: 9, classroom: 2, title: "안내")])
        let board = ProposalBoard.build(lms: inbox(snapshot))
        #expect(board.groups.map(\.group) == [.new, .posts])
        #expect(board.count == 2)
        #expect(board.room(2)?.proposals.map(\.kind) == [.lmsNotice])

        let fileOnly = ProposalBoard.build(
            lms: inbox(LMSSnapshot(at: now, classrooms: [room], files: [.init(id: 200, classroom: 1, title: "Flows")])))
        #expect(fileOnly.groups.map(\.group) == [.new])
    }

    @Test func roomsWithOnlyHiddenItemsStaySoTheyCanBeProposedAgain() {
        var settings = LMSSettings(known: [1])
        settings.mark([LMSKey(kind: .file, id: 200)], handled: true)
        let lms = LMSInbox.build(
            LMSSnapshot(at: now, classrooms: [room], files: [.init(id: 200, classroom: 1, title: "Flows")]), settings: settings,
            courses: [],
            now: now)
        let board = ProposalBoard.build(lms: lms)
        #expect(board.rooms.map(\.id) == [1])
        #expect(board.rooms[0].proposals.isEmpty)
        #expect(board.rooms[0].hidden.map(\.id) == ["file:200"])
        #expect(board.isEmpty)
    }

    @Test func everyKindIsDeclared() {
        for kind in ProposalKind.allCases {
            #expect(!kind.name.isEmpty)
            #expect(kind.picksCourse ? kind.list != nil : true)
        }
        #expect(ProposalGroup.allCases.allSatisfy { g in ProposalKind.allCases.contains { $0.group == g } })
    }
}
