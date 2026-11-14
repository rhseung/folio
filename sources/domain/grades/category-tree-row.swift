import Algorithms
import Foundation

public struct CategoryTreeRow: Sendable, Equatable {
    public var category: Category
    public var depth: Int
    public var group: String

    public init(category: Category, depth: Int, group: String) {
        self.category = category
        self.depth = depth
        self.group = group
    }
}
