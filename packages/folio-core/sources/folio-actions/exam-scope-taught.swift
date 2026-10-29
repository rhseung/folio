import FolioDomain
import Foundation

/// Puts every unit taught before the exam into its scope, with their parent units. Units already in scope stay; none
/// are taken out.
@Action("exam scope --taught", "시험 전에 배운 단원을 모두 범위에 넣기", done: "배운 단원을 시험 '{exam}'의 범위에 넣었습니다", cli: .manual)
public struct ExamScopeTaught {
    @Arg var course: Course.ID
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let e = f.exams[try index(exam, in: f.exams, "시험")]
            guard let start = e.start else { throw ActionError.rule("\(e.title)에 일시가 없어 지난 회차를 알 수 없습니다") }
            f.addScope(f.unitsTaught(before: start), exam: exam)
        }
    }
}
