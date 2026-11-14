import Foundation

public struct Category: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    public var group: String
    public var isMajor: Bool
    public var parentId: UUID?
    public var minCredits: Double?
    public var maxCredits: Double?
    public var minCount: Int?
    public var rule: String?
    public var programId: UUID?
    public var maxSharedCredits: Double?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, name: String, group: String = "", isMajor: Bool = false,
        parentId: UUID? = nil, minCredits: Double? = nil, maxCredits: Double? = nil, minCount: Int? = nil, rule: String? = nil
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.group = group
        self.isMajor = isMajor
        self.parentId = parentId
        self.minCredits = minCredits
        self.maxCredits = maxCredits
        self.minCount = minCount
        self.rule = rule
    }
}
