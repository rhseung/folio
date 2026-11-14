import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "review skip", "단원을 복습하지 않아도 되는 것으로 표시. 단원을 열어 본 시간이 있으면 공부 시간으로 남긴다. 여러 개면 확인을 받는다", effect: .logs,
    confirm: "단원 {units}의 복습을 건너뜁니다.", done: "단원 {units}을(를) 건너뛰었습니다",
    phrases: ["복습 안 해도", "복습 빼기", "복습 건너뛰기", "복습 필요 없음"], cli: .manual(reason: "<과목>/<단원>마다 과목이 달라도 되는 대상(Target) 목록을 만든다"))
public struct ReviewSkip {
    public struct Target: Codable, Sendable, Equatable {
        public var course: UUID
        public var unit: UUID
        public init(course: UUID, unit: UUID) {
            self.course = course
            self.unit = unit
        }
    }
    var units: [Target]
    /// 단원을 연 시각. 끝 시각과 함께, 단원 하나에만 준다
    var start: Date?
    /// 건너뛴 시각
    var end: Date?

    public func run(_ ctx: ActionContext) throws {
        guard let start, let end else {
            guard start == nil, end == nil else { throw ActionError.rule(String(localized: .errorReviewSkipTimes)) }
            for t in units { try ctx.log(ReviewEvent(unitId: t.unit, result: .skip, seconds: 0), course: t.course) }
            return
        }
        guard units.count == 1, let t = units.first else { throw ActionError.rule(String(localized: .errorReviewSkipTimes)) }
        guard end >= start else { throw ActionError.rule(String(localized: .errorReviewEndBeforeStart)) }
        try ctx.log(
            ReviewEvent(unitId: t.unit, result: .skip, seconds: Int(end.timeIntervalSince(start).rounded())), course: t.course, at: end)
        try ctx.log(StudySessionEvent(courseId: t.course, start: start, end: end, screen: "review"), course: t.course, at: end)
    }
}
