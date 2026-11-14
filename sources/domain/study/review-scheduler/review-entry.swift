import Foundation

public struct ReviewEntry: Sendable, Equatable {
    public var item: ReviewScheduler.Item
    public var courseId: UUID
    public var unitTitle: String
}
