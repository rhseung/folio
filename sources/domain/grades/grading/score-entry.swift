import Foundation

public struct ScoreEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var componentId: UUID
    public var title: String
    public var score: Double
    public var max: Double
    public var mean: Double?
    public var stdDev: Double?
    public var date: LocalDate?
    public var assignmentId: UUID?
    public var examId: UUID?
    public var excused: Bool

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, componentId: UUID, title: String, score: Double, max: Double,
        mean: Double? = nil, stdDev: Double? = nil, excused: Bool = false
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.componentId = componentId
        self.title = title
        self.score = score
        self.max = max
        self.mean = mean
        self.stdDev = stdDev
        self.excused = excused
    }
}
