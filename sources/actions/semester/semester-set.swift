import FolioDomain
import FolioStorage
import Foundation

@Action(
    "semester set", "학기의 기간, 시험 주차, 인정 학점 바꾸기. 준 것만 바꾼다", done: "학기 '{semester}'을(를) 바꿨습니다",
    examples: [
        "folio semester set 2026-3 --end 2026-12-18",
        "folio semester set 2026-3 --midterm-week 8 --final-week 16",
        "folio semester set 2026-3 --final-week none --dry-run",
    ],
    phrases: ["개강 종강 날짜", "시험 주차", "종강일 바꾸기", "중간고사 주차", "개강일"])
public struct SemesterSet {
    /// 학기. 2026-3 또는 "2026 fall"
    @Arg var semester: Semester.ID
    /// 개강일
    var start: Patch<LocalDate?>
    /// 종강일
    var end: Patch<LocalDate?>
    /// 중간고사 주차
    var midtermWeek: Patch<Int?>
    /// 기말고사 주차
    var finalWeek: Patch<Int?>
    /// 인정학기의 인정 학점
    var creditedHours: Patch<Double?>

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { t in
            try t.update(\.semesters, semester) { s in
                start.apply(&s.start)
                end.apply(&s.end)
                midtermWeek.apply(&s.midtermWeek)
                finalWeek.apply(&s.finalWeek)
                creditedHours.apply(&s.creditedHours)
                s.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
