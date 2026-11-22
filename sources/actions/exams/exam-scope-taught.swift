import FolioDomain
import Foundation

@Action(
    "exam scope --taught", "시험 범위를 지난 시험 이후 배운 단원으로 되돌리기", done: "시험 '{exam}'의 범위를 배운 단원으로 되돌렸습니다",
    cli: .manual(reason: "명령이 아니라 exam scope의 --taught 플래그라 exam scope가 함께 받는다"), panel: true)
public struct ExamScopeTaught {
    @Arg var course: Course.ID
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let e = f.exams[try index(exam, in: f.exams, .valueExam)]
            guard e.start != nil else { throw ActionError.rule(String(localized: .errorExamNoStart(e.title))) }
            f.resetScope(exam: exam)
        }
    }
}
