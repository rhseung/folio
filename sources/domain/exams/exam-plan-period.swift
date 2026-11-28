import FolioCore
import Foundation

// 시험마다 정하는 공부 기간이다. 앱은 이 기간 안에 정리 노트를 순서대로 놓는다. 끝낼 날은 시험 전날이 아니어도 된다.
public struct ExamPlanPeriod: Codable, Sendable, Equatable, Hashable {
    // 끝낼 날 다음 날부터 시험 전날까지의 날에 두는 것이다.
    public enum After: String, Codable, Sendable, CaseIterable {
        case empty, mock
    }

    public var start: LocalDate
    public var end: LocalDate
    public var after: After

    public init(start: LocalDate, end: LocalDate, after: After = .empty) {
        self.start = start
        self.end = end
        self.after = after
    }

    // 기간을 정하지 않은 시험은 계획을 처음 놓는 공부일부터 시험 전날까지다.
    public static func standard(today: LocalDate, examDay: LocalDate) -> ExamPlanPeriod {
        let end = examDay.adding(days: -1)
        return ExamPlanPeriod(start: min(today, end), end: end)
    }

    // 저장한 기간을 지금의 시험 날짜에 맞춘다. `old`는 이 기간을 저장할 때의 시험 날이다.
    // 끝낼 날이 그때의 시험 전날이면 새 시험 전날로 따라간다. 처음 놓을 때 저장한 기본 기간은 사용자가 고른 기간과 구별되지 않아서,
    // 따라가지 않으면 시험을 늦췄을 때 끝낼 날이 예전 전날에 남고 그 뒤가 빈 날이 된다.
    // 그보다 일찍 끝내기로 한 기간은 그대로 두고, 시험 날을 넘은 끝낼 날만 시험 전날로 당긴다. 시작일이 끝낼 날보다 뒤면 함께 당긴다.
    public func fitted(before examDay: LocalDate, from old: LocalDate? = nil) -> ExamPlanPeriod {
        let eve = examDay.adding(days: -1)
        let follows = old.map { end == $0.adding(days: -1) } ?? false
        let last = follows ? eve : min(end, eve)
        return ExamPlanPeriod(start: min(start, last), end: last, after: after)
    }

    public var isValid: Bool { start <= end }
}
