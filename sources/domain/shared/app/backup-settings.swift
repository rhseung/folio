import Foundation

public struct BackupSettings: Codable, Sendable, Equatable {
    public var enabled = true
    public var folder = "~/Backups/Folio/auto"
    public var dailyDays = 30

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = try c.value(.enabled, or: d.enabled)
        folder = try c.value(.folder, or: d.folder)
        dailyDays = try c.value(.dailyDays, or: d.dailyDays)
    }
}
