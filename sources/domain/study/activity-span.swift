import Foundation

public struct ActivitySpan: Sendable, Equatable {
    // 입력이 이만큼 없으면 쉰 것으로 보고 공부 시간을 끊는다. 설정(`idleMinutes`)에서 온다.
    public let idleLimit: TimeInterval
    public private(set) var start: Date
    public private(set) var lastInput: Date

    public init(start: Date, idleMinutes: Int = SettingItem.idleMinutes.int) {
        self.start = start
        self.lastInput = start
        self.idleLimit = TimeInterval(Swift.max(0, idleMinutes)) * 60
    }

    public mutating func input(at date: Date) -> DateInterval? {
        defer { lastInput = date }
        guard date.timeIntervalSince(lastInput) > idleLimit else { return nil }
        // 시계가 뒤로 가면 `lastInput`이 `start`보다 앞설 수 있다. `DateInterval`은 끝이 시작보다 앞서면 멈춘다.
        let done = DateInterval(start: start, end: Swift.max(start, lastInput + idleLimit))
        start = date
        return done
    }

    public func end(at date: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, min(date, lastInput + idleLimit)))
    }
}
