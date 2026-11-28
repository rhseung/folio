import Foundation

// 늦게 낸 과제가 받을 수 있는 점수를 정한다. 과목에 기본값(`GradePolicy.lateRule`)을 두고 과제마다 덮어쓴다(`Assignment.lateRule`).
public struct LateRule: Codable, Sendable, Equatable {
    // 하루 늦을 때마다 만점에서 깎는 백분율이다.
    public var percentPerDay: Double
    // 마감 뒤 며칠까지 받는지다. 이 날수를 넘기면 0점이다. nil이면 감점이 만점을 다 깎을 때까지 받는다.
    public var days: Int?

    public init(percentPerDay: Double, days: Int? = nil) {
        self.percentPerDay = percentPerDay
        self.days = days
    }

    public var isValid: Bool { (0...100).contains(percentPerDay) && (days ?? 0) >= 0 }

    // 늦게 낸 과제에 점수를 줄 수 있는지다. `0:0`만이 아니라 하루에 100%를 깎는 규칙도 하루만 늦어도 0점이므로 받지 않는 규칙이다.
    public var acceptsLate: Bool { ceiling(lateDays: 1) > 0 }

    // 받을 수 있는 최대 점수를 만점에 대한 비율(0...1)로 돌려준다.
    public func ceiling(lateDays: Int) -> Double {
        guard lateDays > 0 else { return 1 }
        if let days, lateDays > days { return 0 }
        return max(0, 1 - percentPerDay / 100 * Double(lateDays))
    }

    // 마감은 달력 시각으로 세므로 하루는 공부일이 아니라 마감에서부터의 24시간이다. 1초라도 늦으면 하루 늦은 것이다.
    public static func lateDays(due: Date, at date: Date) -> Int {
        let late = date.timeIntervalSince(due)
        return late <= 0 ? 0 : Int((late / 86_400).rounded(.up))
    }

    // 감점이 바뀌는 다음 시각이다. 이미 0점이면 nil이다.
    public func nextDrop(due: Date, at date: Date) -> Date? {
        let days = Self.lateDays(due: due, at: date)
        guard ceiling(lateDays: days) > 0 else { return nil }
        return due + Double(days) * 86_400
    }
}
