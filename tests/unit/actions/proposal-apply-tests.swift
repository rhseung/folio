import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ProposalApplyTests {
    static let graphTheory = ActionTests.graphTheory
    let exam = UUID()
    let proposal = ActionProposal(id: UUID(), command: "exam add", input: .null)

    func apply(on gist: GISTStore, device: DeviceID, at now: Date) throws {
        let ctx = ActionContext(gist: gist, device: device, now: now)
        ctx.proposal = proposal
        try ExamAdd(id: exam, course: Self.graphTheory, title: "기말고사").run(ctx)
    }

    func file(_ gist: GISTStore) throws -> CourseFile { try ActionContext(gist: gist, device: UUID()).file(Self.graphTheory) }

    @Test func theDocumentAndDeviceLogRecordTheProposal() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let device = UUID()
        try apply(on: gist, device: device, at: .now)
        let id = try #require(proposal.id)
        #expect(try file(gist).hasApplied(id))
        let store = try ActionContext(gist: gist, device: device).store(Self.graphTheory)
        let events = try store.log.readAll().events(ProposalAppliedEvent.self)
        #expect(events.map(\.event.proposal) == [id])
    }

    @Test func applyingTwiceIsRefusedWithoutWriting() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try apply(on: gist, device: UUID(), at: .now)
        let once = try file(gist)
        #expect(throws: ActionError.applied) { try apply(on: gist, device: UUID(), at: .now) }
        #expect(try file(gist) == once)
    }

    // 두 기기가 같은 제안을 거의 함께 적용하면 iCloud가 사본 둘을 남긴다. 합친 결과는 한 번 적용한 것과 같다.
    @Test func mergingTwoDevicesCopiesEqualsOneApplication() throws {
        let fixture = try Fixture.standard.copyToTemp()
        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: copy)
        let first = GISTStore(url: fixture), second = GISTStore(url: copy)
        try apply(on: first, device: UUID(), at: Date(timeIntervalSince1970: 1_790_000_000))
        try apply(on: second, device: UUID(), at: Date(timeIntervalSince1970: 1_790_000_060))
        let a = try file(first), b = try file(second)
        #expect(a.merged(with: b) == b)
        #expect(b.merged(with: a) == b)
        #expect(b.merged(with: a).exams.filter { $0.id == exam }.count == 1)
    }

    // 파일을 먼저 쓰는 액션도 있으므로, 이미 남은 제안은 액션을 실행하기 전에 멈춘다.
    @Test func anAppliedProposalIsRefusedBeforeTheActionRuns() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try apply(on: gist, device: UUID(), at: .now)
        let again = ActionContext(gist: gist, device: UUID())
        again.proposal = proposal
        #expect(throws: ActionError.applied) { try again.refuseAppliedProposal() }
        let fresh = ActionContext(gist: gist, device: UUID())
        fresh.proposal = ActionProposal(id: UUID(), command: "exam add", input: .null)
        try fresh.refuseAppliedProposal()
    }

    // `assignment status`는 과제를 따로 touch하지 않는다. 다른 기기가 나중에 다른 항목을 고친 사본과 합쳐도 상태가 남아야 한다.
    @Test func anEditOnOneDeviceSurvivesALaterEditOfAnotherItem() throws {
        let fixture = try Fixture.standard.copyToTemp()
        let homework = UUID()
        try AssignmentAdd(id: homework, course: Self.graphTheory, title: "HW 9")
            .run(ActionContext(gist: GISTStore(url: fixture), device: UUID(), now: Date(timeIntervalSince1970: 1_789_000_000)))
        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: copy)
        let first = GISTStore(url: fixture), second = GISTStore(url: copy)
        let status = AssignmentStatus.submitted
        try AssignmentStatusSet(course: Self.graphTheory, assignment: homework, status: status)
            .run(ActionContext(gist: first, device: UUID(), now: Date(timeIntervalSince1970: 1_790_000_000)))
        try ExamAdd(id: exam, course: Self.graphTheory, title: "기말고사")
            .run(ActionContext(gist: second, device: UUID(), now: Date(timeIntervalSince1970: 1_790_000_060)))
        let a = try file(first), b = try file(second)
        for merged in [a.merged(with: b), b.merged(with: a)] {
            #expect(merged.assignments.first { $0.id == homework }?.status == status)
            #expect(merged.exams.contains { $0.id == exam })
        }
    }
}
