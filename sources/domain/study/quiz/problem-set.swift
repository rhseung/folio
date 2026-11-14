import Foundation

public struct ProblemSet: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public struct Problem: Codable, Sendable, Equatable {
        public var number: String
        public var page: Int?
        public var unitIds: [UUID]
        public var category: CardCategory?

        public init(number: String, page: Int? = nil, unitIds: [UUID] = [], category: CardCategory? = nil) {
            self.number = number
            self.page = page
            self.unitIds = unitIds
            self.category = category
        }
    }

    public var title: String
    public var materialId: UUID?
    public var solutionMaterialId: UUID?
    public var problems: [Problem]

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, problems: [Problem] = []) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.problems = problems
    }
}
