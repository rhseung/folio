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

    // 시험 날짜가 앞당겨지면 저장한 기간이 시험 날을 넘는다. 끝낼 날을 시험 전날로 당기고 시작일이 그 뒤면 함께 당긴다.
    public func fitted(before examDay: LocalDate) -> ExamPlanPeriod {
        let last = min(end, examDay.adding(days: -1))
        return ExamPlanPeriod(start: min(start, last), end: last, after: after)
    }

    public var isValid: Bool { start <= end }
}
