import FolioDomain
import FolioStorage
import Foundation

@Action(
    "transcript add", "지난 학기나 인정학기 과목의 성적 기록 추가. 과목 폴더와 course.json을 만든다", effect: .creates, done: "과목 '{title}'의 기록을 추가했습니다",
    examples: [#"folio transcript add "영재고 AP" "일반물리학 및 연습 II" --code GS --number 1102 --mode pass_fail --dry-run  인정학기 과목"#],
    phrases: ["인정학기 과목", "성적 기록 추가", "지난 학기 과목"])
public struct TranscriptAdd {
    @New var id: Course.ID
    /// 학기
    @Arg var semester: Semester.ID
    /// 과목 이름
    @Arg var title: String
    /// 강의 코드. 과목 폴더 이름이 된다
    var code: CourseCode.ID
    /// 과목 번호. 예: 4207
    var number: String
    /// 학점
    var credits: Double = 3
    /// 평가 방식
    var mode: GradingMode = .passFail
    /// 받은 성적
    var grade: LetterGrade.ID?

    public func run(_ ctx: ActionContext) throws {
        var course = Course(
            id: id, device: ctx.device, at: ctx.now, semesterId: semester, title: title, codes: [code], number: number,
            credits: credits, gradingMode: mode)
        course.finalGrade = grade
        try CourseAdd.create(course, ctx)
        ctx.made(id)
    }
}
