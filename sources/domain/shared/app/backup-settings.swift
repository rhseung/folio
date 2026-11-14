import Foundation

public struct BackupSettings: Codable, Sendable, Equatable {
    public var enabled = SettingItem.backupEnabled.bool
    public var folder = SettingItem.backupFolder.text
    public var dailyDays = SettingItem.backupDailyDays.int

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = try c.value(.enabled, or: d.enabled)
        folder = try c.value(.folder, or: d.folder)
        dailyDays = try c.value(.dailyDays, or: d.dailyDays)
    }
}
