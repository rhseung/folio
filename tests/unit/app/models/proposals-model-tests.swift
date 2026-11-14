import FolioActions
import FolioDomain
import FolioLMS
import Foundation
import Testing

@testable import Folio

@MainActor
struct ProposalsModelTests {
    static let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!

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

    @Test func firstSyncMarksWhatClassroomsHoldAndProposesOpenAssignments() async throws {
        let workspace = try workspace(Self.snapshot)
        let model = ProposalsModel(workspace: workspace)
        #expect(model.sections.isEmpty)

        await workspace.syncLMS()
        #expect(workspace.settings.lms.known == [1, 2])
        #expect(model.waiting.map(\.classroom.title) == ["그래프 이론[01]"])
        #expect(model.inbox.proposals.map(\.id) == ["assignment:100"])
        #expect(model.sections.map(\.id) == [1, 2])
        #expect(model.sections.map { $0.handled.map(\.id) } == [["file:200"], ["notice:300"]])
        #expect(model.total == 1)
        #expect(model.earliestDue?.contains("Homework Set #5") == true)
    }

    @Test func eachProposalGoesToTheCoursePickedAndDismissingHidesIt() async throws {
        let workspace = try workspace(Self.snapshot)
        await workspace.syncLMS()
        workspace.run(LMSMark(keys: ["file:200", "notice:300"], handled: false))
        let model = ProposalsModel(workspace: workspace)
        #expect(model.sections.map(\.id) == [1, 2])
        let proposals = model.inbox.proposals
        #expect(proposals.map(\.id) == ["assignment:100", "file:200", "notice:300"])
        #expect(proposals.map(model.canAdd) == [true, true, false])
        #expect(model.targets.contains { $0.id == Self.graphTheory })

        await model.add([proposals[0]], into: Self.graphTheory)
        #expect(workspace.course(Self.graphTheory)?.file.assignments.filter { $0.lmsId == 100 }.count == 1)
        model.dismiss([proposals[2]])
        await model.add([proposals[1]], into: Self.graphTheory)
        #expect(model.inbox.proposals.map(\.id) == ["file:200"])
        let left = try #require(model.inbox.proposals.first)
        #expect(!model.canAdd(left) && model.isViewerOnly(left))

        let handled = model.sections.flatMap(\.handled)
        let added = try #require(handled.first { $0.id == "assignment:100" })
        #expect(!model.canProposeAgain(added) && model.detail(added).contains("그래프 이론"))
        let notice = try #require(handled.first { $0.id == "notice:300" })
        #expect(model.canProposeAgain(notice))
        model.proposeAgain(notice)
        #expect(model.inbox.proposals.map(\.id) == ["file:200", "notice:300"])
    }
}
