import Foundation

public struct Assignment: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var due: Date?
    public var status: AssignmentStatus
    public var componentId: UUID?
    public var componentGroup: String?
    public var repeats: AssignmentRepeat?
    public var problemMaterialId: UUID?
    public var submissionMaterialIds: [UUID]
    public var unitIds: [UUID]
    public var source: AssignmentSource
    public var lmsId: Int?
    public var memo: String

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, due: Date? = nil, source: AssignmentSource = .manual) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.due = due
        self.status = .todo
        self.submissionMaterialIds = []
        self.unitIds = []
        self.source = source
        self.memo = ""
    }
}
