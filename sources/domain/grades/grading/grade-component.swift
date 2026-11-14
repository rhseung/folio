import Foundation

public struct GradeComponent: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    public var weight: Double
    public var order: Int
    public var aggregation: Aggregation
    public var expectedCount: Int?
    public var group: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, name: String, weight: Double, order: Int = 0, aggregation: Aggregation = .sum,
        expectedCount: Int? = nil
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.weight = weight
        self.order = order
        self.aggregation = aggregation
        self.expectedCount = expectedCount
    }
}
