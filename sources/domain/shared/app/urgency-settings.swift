import Foundation

public struct UrgencySettings: Codable, Sendable, Equatable {
    public var assignmentUrgentDays = SettingItem.assignmentUrgentDays.int
    public var assignmentSoonDays = SettingItem.assignmentSoonDays.int
    public var examUrgentDays = SettingItem.examUrgentDays.int
    public var examSoonDays = SettingItem.examSoonDays.int
    public var examNearDays = SettingItem.examNearDays.int

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        assignmentUrgentDays = try c.value(.assignmentUrgentDays, or: d.assignmentUrgentDays)
        assignmentSoonDays = try c.value(.assignmentSoonDays, or: d.assignmentSoonDays)
        examUrgentDays = try c.value(.examUrgentDays, or: d.examUrgentDays)
        examSoonDays = try c.value(.examSoonDays, or: d.examSoonDays)
        examNearDays = try c.value(.examNearDays, or: d.examNearDays)
    }
}
