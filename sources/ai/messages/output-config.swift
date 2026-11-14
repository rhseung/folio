import FolioDomain
import Foundation

public struct OutputConfig: Codable, Sendable, Equatable {
    public struct Format: Codable, Sendable, Equatable {
        public var type = "json_schema"
        public var schema: JSONValue
    }

    public var effort: Effort?
    public var format: Format?
}
