import Foundation

public struct LinkQuery: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        case target
        case heading
        case block
        case page
    }

    public var part: Part
    public var embed: Bool
    public var target: String
    public var alias: String?

    public init(part: Part, embed: Bool = false, target: String = "", alias: String? = nil) {
        self.part = part
        self.embed = embed
        self.target = target
        self.alias = alias
    }
}
