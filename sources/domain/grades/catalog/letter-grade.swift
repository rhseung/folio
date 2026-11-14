import Foundation

public struct LetterGrade: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var symbol: String
    public var points: Double?
    public var countsInGpa: Bool
    public var countsInCredits: Bool
    public var countsTowardGraduation: Bool?
    public var earnsCredits: Bool { countsTowardGraduation ?? countsInCredits }
    public var modes: [GradingMode]?

    public func applies(to mode: GradingMode) -> Bool {
        modes.map { $0.contains(mode) } ?? (points == nil || mode != .passFail)
    }

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, symbol: String, points: Double?, countsInGpa: Bool, countsInCredits: Bool
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.symbol = symbol
        self.points = points
        self.countsInGpa = countsInGpa
        self.countsInCredits = countsInCredits
    }
}
