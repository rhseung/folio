import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam summary", "시험 종합 정리 노트. 없으면 템플릿으로 만든다", effect: .creates, done: "시험 '{exam}'의 종합 정리 노트",
    examples: ["folio exam summary EC4207/중간고사"], phrases: ["시험 정리 노트", "요약 노트", "족보 정리"])
public struct ExamSummary {
    @New var note: Note.ID
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        let file = try ctx.file(course)
        let exam = file.exams[try index(exam, in: file.exams, .valueExam)]
        if let existing = try ctx.notes(course).first(where: { $0.meta.kind == .examSummary && $0.meta.examId == exam.id })?.meta.id {
            ctx.made(existing)
            return
        }

        let settings = try ctx.settings()
        let title = "\(exam.title) 종합 정리"
        let body = NoteTemplate.body(for: .examSummary, title: title, sections: settings.noteSections(for: .examSummary))
        let meta = NoteMeta(id: note, kind: .examSummary, examId: exam.id, math: settings.newNoteMath)
        ctx.made(try ctx.createNote(course, title: title, meta: meta, body: body))
    }
}
