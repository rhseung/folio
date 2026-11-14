import Foundation

public struct Person: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    public var email: String
    public var role: PersonRole
    public var office: String
    public var officeHours: String
    public var memo: String

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, name: String, email: String = "", role: PersonRole = .professor,
        office: String = "", officeHours: String = "", memo: String = ""
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.email = email
        self.role = role
        self.office = office
        self.officeHours = officeHours
        self.memo = memo
    }
}
