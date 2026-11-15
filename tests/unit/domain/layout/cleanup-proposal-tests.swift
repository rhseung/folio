import FolioDomain
import Foundation
import Testing

struct CleanupProposalTests {
    let plan = CleanupPlan(
        moves: [
            PlannedMove(from: "2026-3/그래프/강의/1주.pdf", to: "2026-3/EC4207 그래프 이론/Lectures/01_1주.pdf"),
            PlannedMove(from: "2026-3/그래프/과제/hw.pdf", to: "2026-3/EC4207 그래프 이론/Assignments/HW01/hw.pdf", review: .guessedNumber),
        ], skipped: [])

    @Test func eachMoveIsAProposalAndTheReviewMarkIsItsFlag() {
        let proposals = plan.proposals
        #expect(proposals.map(\.kind) == [.cleanupMove, .cleanupMove])
        #expect(proposals.map(\.flag) == [nil, .review(.guessedNumber)])
        #expect(proposals[1].flag?.label == ReviewReason.guessedNumber.label)
        #expect(proposals.allSatisfy { $0.canApprove && !$0.canDismiss })
        #expect(proposals[0].title == plan.moves[0].from)
    }

    @Test func flaggedMovesNeedToBeIncludedOnPurpose() {
        #expect(plan.approved(includeFlagged: false) == [plan.moves[0]])
        #expect(plan.approved(includeFlagged: true) == plan.moves)
    }

    @Test func approvingSeveralMovesIsOneCleanupForTheCourse() throws {
        let course = UUID()
        let approvals = plan.proposals.approvals(in: course)
        #expect(approvals.count == 1)
        #expect(approvals[0].command == "cleanup apply")
        #expect(approvals[0].input["course"] == .string(course.uuidString))
        guard case .array(let moves)? = approvals[0].input["moves"] else { Issue.record("no moves"); return }
        #expect(moves.count == 2)
        #expect(moves[1]["review"] == "guessedNumber")
    }

    @Test func movesForDifferentCoursesStaySeparate() {
        let p = plan.proposals
        let a = Proposal(kind: .cleanupMove, source: p[0].source, action: p[0].action(in: UUID()))
        let b = Proposal(kind: .cleanupMove, source: p[1].source, action: p[1].action(in: UUID()))
        #expect([a, b].approvals(in: nil).count == 2)
    }
}
