import FolioDomain
import FolioStorage
import Foundation

@Action(
    "assignment status", "과제 상태 바꾸기. 매주 과제를 내면 다음 과제가 생긴다", done: "과제 '{assignment}'의 상태를 {status}(으)로 바꿨습니다",
    examples: ["folio assignment status EC4207/HW3 submitted"], phrases: ["제출", "냈어", "다 했어", "하는 중", "채점됨"])
public struct AssignmentStatusSet {
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID
    /// 상태
    @Arg var status: AssignmentStatus

    public func run(_ ctx: ActionContext) throws {
        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            let i = try index(assignment, in: f.assignments, .valueAssignment)
            f.assignments[i].status = status
            f.continueRepeating(assignment, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
        }
    }
}
