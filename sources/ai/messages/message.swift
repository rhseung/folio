import FolioDomain
import Foundation

public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var content: [ContentBlock]

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}
