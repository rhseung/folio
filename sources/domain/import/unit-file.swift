import Foundation

public struct UnitFile: Codable, Sendable {
    public var course: String
    public var units: [UnitSpec]
}
