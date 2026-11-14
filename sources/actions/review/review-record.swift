import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// MARK: Review

@Action(
    "review record", "단원 복습 결과와 걸린 시간을 기록", effect: .logs, done: "단원 '{unit}'의 복습을 기록했습니다",
    examples: [#"folio review record EC4207/매칭 good --start "2026-10-28 20:00" --end "2026-10-28 20:40""#],
    phrases: ["복습했", "공부했", "복습 완료", "복습 기록", "공부함"])
public struct ReviewRecord {
    /// 과목
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 결과
    @Arg var result: ReviewResult
    /// 시작 시각
    var start: Date
    /// 끝난 시각
    var end: Date

    public func run(_ ctx: ActionContext) throws {
        guard result != .skip else { throw ActionError.rule(String(localized: .errorReviewRecordSkip)) }
        guard end >= start else { throw ActionError.rule(String(localized: .errorReviewEndBeforeStart)) }
        try ctx.log(
            ReviewEvent(unitId: unit, result: result, seconds: Int(end.timeIntervalSince(start).rounded())), course: course, at: end)
        try ctx.log(StudySessionEvent(courseId: course, start: start, end: end, screen: "review"), course: course, at: end)
    }
}
