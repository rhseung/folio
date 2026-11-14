import FolioDomain
import Foundation

public struct MoveRecord: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable {
        case move
        case makeFolder
        case removeFolder
        case removeJunk
        case fileCourse
        case unfileCourse
    }

    public var schemaVersion: Int
    public var id: UUID
    public var batch: UUID
    public var undoOf: UUID?
    public var at: Date
    public var device: DeviceID
    public var op: Op
    public var from: String?
    public var to: String?
}
