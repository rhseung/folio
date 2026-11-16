import Foundation

public struct SearchHit: Sendable, Hashable {
    public var item: SearchItem
    public var snippet: String?

    public init(item: SearchItem, snippet: String? = nil) {
        self.item = item
        self.snippet = snippet
    }
}
