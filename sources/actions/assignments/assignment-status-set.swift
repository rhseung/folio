import FolioDomain
import FolioStorage
import Foundation

@Action(
    "assignment status", "과제 상태 바꾸기. 매주 과제를 내면 다음 과제가 생긴다", done: "과제 '{assignment}'의 상태를 {status}(으)로 바꿨습니다",
    examples: [
        "folio assignment status EC4207/HW3 submitted", #"folio assignment status EC4207/HW3 submitted --at "2026-11-07 01:20""#,
        "folio assignment status EC4207/SP01 missed",
    ], phrases: ["제출", "냈어", "다 했어", "하는 중", "채점됨", "못 냈어", "포기", "안 내기로"], panel: true)
public struct AssignmentStatusSet {
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID
    /// 상태. todo, doing, submitted, graded, missed(못 냄)
    @Arg var status: AssignmentStatus
    /// 낸 시각. submitted와 graded에만 쓰고, 빼면 이미 남긴 시각이나 지금이다
    @CLIName("at") var submittedAt: Date?

    public func run(_ ctx: ActionContext) throws {
        if submittedAt != nil, status != .submitted, status != .graded {
            throw ActionError.input(String(localized: .errorAssignmentSubmittedAtStatus))
        }
        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            let i = try index(assignment, in: f.assignments, .valueAssignment)
            f.assignments[i].set(status, submittedAt: submittedAt, now: ctx.now)
            f.continueRepeating(assignment, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
        }
    }
}
