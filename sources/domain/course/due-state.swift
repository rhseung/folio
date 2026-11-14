import Foundation

// 마감까지 남은 시간은 공부일 경계가 아니라 실제 시각으로 센다.
public enum DueState: Equatable, Sendable {
    case none
    case overdue(days: Int)
    case hours(Int)
    case days(Int)

    public init(due: Date?, now: Date, calendar: Calendar) {
        guard let due else { self = .none; return }
        if due < now {
            self = .overdue(days: max(0, calendar.dateComponents([.day], from: due, to: now).day ?? 0))
        } else if due.timeIntervalSince(now) < 24 * 3600 {
            self = .hours(Int((due.timeIntervalSince(now) / 3600).rounded(.up)))
        } else {
            self = .days(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0)
        }
    }
}
