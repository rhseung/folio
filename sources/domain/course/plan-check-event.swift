import Foundation

public struct PlanCheckEvent: LogEvent, Equatable {
    public static let type = "plan_check"
    public var itemId: UUID
    public var done: Bool
    public var auto: Bool

    public init(itemId: UUID, done: Bool, auto: Bool = false) {
        self.itemId = itemId
        self.done = done
        self.auto = auto
    }
}
