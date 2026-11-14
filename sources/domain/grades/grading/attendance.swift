import Foundation

public struct Attendance: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var sessionId: UUID
    public var state: AttendanceState

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, sessionId: UUID, state: AttendanceState) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.sessionId = sessionId
        self.state = state
    }
}
