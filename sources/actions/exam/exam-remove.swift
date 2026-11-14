import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam rm", "시험 기록 지우기. 시험 폴더와 파일은 남는다. 범위 단원과 점수의 연결도 풀린다", effect: .removes,
    confirm: "시험 '{exam}'의 기록을 지웁니다. 폴더와 파일은 남습니다.", done: "시험 '{exam}'을(를) 지웠습니다",
    examples: ["folio exam rm EC4207/Quiz1 --dry-run"], phrases: ["시험 삭제"])
public struct ExamRemove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(exam, in: f.exams, .valueExam)
            try f.remove(Exam.self, exam)
        }
    }
}
