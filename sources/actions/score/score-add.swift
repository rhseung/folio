import FolioDomain
import FolioStorage
import Foundation

// MARK: Grades

@Action(
    "score add", "점수 추가", effect: .creates, done: "점수 '{id}'을(를) 추가했습니다",
    examples: [
        "folio score add EC4207 --component 과제 --title HW1 --score 9 --max 10",
        "folio score add EC4207 --component 중간고사 --score 72 --max 100 --mean 61.5 --std-dev 12 --date 2026-10-21 --dry-run",
    ],
    phrases: ["점수 입력", "점수 기록", "성적 나왔어", "몇 점 받았어", "평균 표준편차"])
public struct ScoreAdd {
    @New var id: ScoreEntry.ID
    /// 과목
    @Arg var course: Course.ID
    /// 성적 항목
    var component: GradeComponent.ID
    /// 제목. 예: HW1
    var title: String = ""
    /// 받은 점수
    var score: Double
    /// 만점
    var max: Double
    /// 평균
    var mean: Double?
    /// 표준편차
    var stdDev: Double?
    /// 날짜. 2026-10-21
    var date: LocalDate?
    /// 점수가 나온 시험
    var exam: Exam.ID?
    /// 점수가 나온 과제
    var assignment: Assignment.ID?
    /// 면제. 계산에서 뺀다
    var excused = false

    public func run(_ ctx: ActionContext) throws {
        var entry = ScoreEntry(
            id: id, device: ctx.device, at: ctx.now, componentId: component, title: title, score: score, max: max, mean: mean,
            stdDev: stdDev,
            excused: excused)
        (entry.date, entry.examId, entry.assignmentId) = (date, exam, assignment)
        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            guard !f.scores.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenScore("\(id)"))) }
            f.scores.append(entry)
            if let assignment { f.scoredAssignment(assignment, until: end, ctx) }
        }
        ctx.made(id)
    }
}
