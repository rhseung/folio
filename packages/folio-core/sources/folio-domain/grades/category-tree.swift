import Algorithms
import Foundation

public struct CategoryTreeRow: Sendable, Equatable {
    public var category: Category
    public var depth: Int
    /// The top-level ancestor's group, so a child stays under it whatever its own group says.
    public var group: String

    public init(category: Category, depth: Int, group: String) {
        self.category = category
        self.depth = depth
        self.group = group
    }
}

extension Category {
    /// Groups of the top-level categories, in catalog order.
    public static func groups(_ categories: [Category]) -> [String] {
        Array(categories.filter { $0.parentId == nil }.map(\.group).uniqued())
    }

    /// Each category followed by its children, depth first. A parent missing from the list makes its child a root
    /// rather than hiding it, and a cycle stops at the first category seen again.
    public static func tree(_ categories: [Category]) -> [CategoryTreeRow] {
        var result: [CategoryTreeRow] = []
        func visit(_ c: Category, depth: Int, group: String) {
            guard !result.contains(where: { $0.category.id == c.id }) else { return }
            result.append(CategoryTreeRow(category: c, depth: depth, group: group))
            for child in categories where child.parentId == c.id { visit(child, depth: depth + 1, group: group) }
        }
        let ids = Set(categories.map(\.id))
        for root in categories where root.parentId.map({ !ids.contains($0) }) ?? true { visit(root, depth: 0, group: root.group) }
        return result
    }
}
