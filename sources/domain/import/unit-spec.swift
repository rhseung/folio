import Foundation

public struct UnitSpec: Codable, Sendable, Equatable {
    public var title: String
    public var sessions: [String]?
    public var children: [UnitSpec]?

    public init(title: String, sessions: [String]? = nil, children: [UnitSpec]? = nil) {
        self.title = title
        self.sessions = sessions
        self.children = children
    }
}
