import Foundation

// 시험까지 남은 날로 정하는 표시의 세기다. 기준은 설정(`urgency`)이다.
public enum ExamUrgency: Int, Comparable, Sendable {
    // 칩이 깜박인다.
    case urgent
    // 위험 색으로 보인다.
    case soon
    // D-day로 센다. 더 멀면 날짜로 보인다.
    case near
    case later

    public init(days: Int, settings: UrgencySettings) {
        self =
            days <= settings.examUrgentDays
            ? .urgent
            : days <= settings.examSoonDays ? .soon : days <= settings.examNearDays ? .near : .later
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
