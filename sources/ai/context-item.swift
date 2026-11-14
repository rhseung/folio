import FolioDomain
import Foundation

public struct ContextItem: Sendable, Equatable, Identifiable {
    public enum Tier: Int, Sendable, Comparable {
        case courseSummary, userRules, focus, related, search
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var title: String
    public var tier: Tier
    public var text: String
    public var images: [Image]

    public struct Image: Sendable, Equatable {
        public var name: String
        public var data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data }
    }

    public init(id: String, title: String, tier: Tier, text: String, images: [Image] = []) {
        self.id = id
        self.title = title
        self.tier = tier
        self.text = text
        self.images = images
    }
}
