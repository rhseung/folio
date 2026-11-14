import FolioDomain
import FolioStorage
import Foundation

@Action(
    "score set", "점수 고치기. 준 것만 바꾼다", done: "점수 '{score}'을(를) 고쳤습니다",
    examples: [
        "folio score set EC4207/HW1 --value 10", "folio score set EC4207/HW1 --excused true",
        "folio score set EC4207/HW1 --date none --dry-run",
    ],
    phrases: ["잘못 넣", "틀리게 넣", "점수 고치기", "점수 수정", "점수 정정"])
public struct ScoreSet {
    @Arg var course: Course.ID
    /// 점수 제목
    @Arg var score: ScoreEntry.ID
    /// 성적 항목
    var component: Patch<GradeComponent.ID>
    /// 제목
    var title: Patch<String>
    /// 받은 점수
    var value: Patch<Double>
    /// 만점
    var max: Patch<Double>
    /// 평균
    var mean: Patch<Double?>
    /// 표준편차
    var stdDev: Patch<Double?>
    /// 날짜
    var date: Patch<LocalDate?>
    /// 점수가 나온 시험
    var exam: Patch<Exam.ID?>
    /// 점수가 나온 과제
    var assignment: Patch<Assignment.ID?>
    /// 면제 여부
    var excused: Patch<Bool>

    public func run(_ ctx: ActionContext) throws {
        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            let linked = f.scores.first { $0.id == score }?.assignmentId
            try f.update(\.scores, score) { e in
                component.apply(&e.componentId)
                title.apply(&e.title)
                value.apply(&e.score)
                max.apply(&e.max)
                mean.apply(&e.mean)
                stdDev.apply(&e.stdDev)
                date.apply(&e.date)
                exam.apply(&e.examId)
                assignment.apply(&e.assignmentId)
                excused.apply(&e.excused)
                e.touch(by: ctx.device, at: ctx.now)
            }
            if case .set(let a?) = assignment, a != linked { f.scoredAssignment(a, until: end, ctx) }
        }
    }
}
