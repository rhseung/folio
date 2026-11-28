import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan add", "공부 계획에 직접 쓴 할 일을 날짜에 추가", effect: .creates, done: "공부 계획에 '{title}'을(를) 넣었습니다",
    examples: [#"folio exam plan add EC4207/기말고사 --day 2026-12-05 "족보 한 번 더 풀기""#], phrases: ["공부 계획", "시험 준비 계획", "날짜별 할 일"], panel: true)
public struct ExamPlanAdd {
    @New var id: ExamPlanItem.ID
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 할 일
    @Arg var title: String
    /// 날짜. 2026-12-03
    var day: LocalDate

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard !e.plan.contains(where: { $0.id == id }) else {
                    throw ActionError.rule(String(localized: .errorIdTakenPlanItem("\(id)")))
                }
                e.plan.append(ExamPlanItem(id: id, day: day, target: .custom, title: title, edited: true))
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
        ctx.made(id)
    }
}
