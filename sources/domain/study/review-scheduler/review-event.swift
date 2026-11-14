import Foundation

public struct ReviewEvent: LogEvent, Equatable {
    public static let type = "review"
    public var unitId: UUID
    public var result: ReviewResult
    public var seconds: Int

    public init(unitId: UUID, result: ReviewResult, seconds: Int) {
        self.unitId = unitId
        self.result = result
        self.seconds = seconds
    }
}
