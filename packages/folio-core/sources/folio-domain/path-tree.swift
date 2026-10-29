import Foundation

public struct PathTree<Item> {
    /// The folder's path; for the root, the folders every item shares (`Assignments`), or empty.
    public var path: String
    public var name: String { (path as NSString).lastPathComponent }
    public var folders: [PathTree]
    public var items: [(name: String, item: Item)]

    /// The shared leading folders are folded into the root, so a list all under `Lectures/` starts at its files.
    public init(_ items: [Item], path: (Item) -> String) {
        self.init(path: "", entries: items.map { (path($0).split(separator: "/").map(String.init), $0) })
        while self.items.isEmpty, folders.count == 1 { self = folders[0] }
    }

    init(path: String, entries: [(parts: [String], item: Item)]) {
        self.path = path
        let (here, deeper) = (entries.filter { $0.parts.count <= 1 }, entries.filter { $0.parts.count > 1 })
        items = here.map { ($0.parts.first ?? "", $0.item) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        folders = Dictionary(grouping: deeper) { $0.parts[0] }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { name, group in
                PathTree(path: path.isEmpty ? name : "\(path)/\(name)", entries: group.map { (Array($0.parts.dropFirst()), $0.item) })
            }
    }

    /// Items here and in every folder below.
    public var count: Int { items.count + folders.reduce(0) { $0 + $1.count } }
}
