import FolioDomain
import Foundation

public protocol StoredModel: Codable {
    static var schemaVersion: Int { get }
    static var migrations: [Int: @Sendable (inout JSONValue) throws -> Void] { get }
}

extension StoredModel {
    public static var migrations: [Int: @Sendable (inout JSONValue) throws -> Void] { [:] }
}
