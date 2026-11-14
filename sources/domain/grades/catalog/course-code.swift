import Foundation

public struct CourseCode: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var prefix: String
    public var department: String
    public var program: String
    public var source: String

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, prefix: String, department: String = "", program: String = "",
        source: String = ""
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.prefix = prefix
        self.department = department
        self.program = program
        self.source = source
    }
}
