import FolioDomain
import FolioStorage
import Foundation

// MARK: Exams

@Action(
    "exam add", "시험 추가. 시험 폴더(Exams/<제목>)는 첫 파일과 함께 생긴다", effect: .creates, done: "시험 '{title}'을(를) 추가했습니다",
    examples: [
        #"folio exam add EC4207 중간고사 --start "2026-10-21 10:00" --end "2026-10-21 12:00" --location B101"#,
        "folio exam add EC4207 Quiz1 --start 2026-09-30 --dry-run",
    ],
    phrases: ["기말고사 추가", "중간고사 등록", "시험 추가", "중간고사 추가", "기말 등록", "퀴즈 일정"])
public struct ExamAdd {
    @New var id: Exam.ID
    /// 과목
    @Arg var course: Course.ID
    /// 시험 제목
    @Arg var title: String
    /// 시작 일시
    var start: Date?
    /// 끝 일시
    var end: Date?
    /// 장소
    var location: String = ""
    /// 반영되는 성적 항목
    var component: GradeComponent.ID?
    /// 범위 단원. 여러 번 줄 수 있다
    var scope: [FolioDomain.Unit.ID] = []
    /// 범위 설명. 예: 3장까지
    var scopeText: String = ""
    /// 허용 자료. 예: 계산기
    var allowed: String = ""
    /// 메모
    var memo: String = ""

    public func run(_ ctx: ActionContext) throws {
        var exam = Exam(id: id, device: ctx.device, at: ctx.now, title: title, start: start, end: end, location: location)
        (exam.componentId, exam.scopeText, exam.allowed, exam.memo) = (component, scopeText, allowed, memo)
        try ctx.edit(course) { f in
            guard !f.exams.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenExam("\(id)"))) }
            exam.folder = MaterialIntake.examFolder(title: title, among: f.exams)
            f.exams.append(exam)
            f.setScope(scope, exam: id)
        }
        ctx.made(id)
    }
}
