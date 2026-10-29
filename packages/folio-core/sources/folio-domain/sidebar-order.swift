import Foundation

/// The order the user dragged each term's courses into in the sidebar. Terms keep their date order. Only ids are kept;
/// a course not listed (a new one) takes its place from the default order, so a list from before it still reads.
public struct SidebarOrder: Codable, Sendable, Equatable {
    /// Every term's courses in one list; each term reads only its own.
    public var courses: [UUID]

    public init(courses: [UUID] = []) {
        self.courses = courses
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courses = try c.value(.courses, or: [])
    }

    /// `ids` (in their default order) rearranged by `stored`. An id missing from `stored` goes in front of the first
    /// stored id that comes after it by default, so a new course sits by its name.
    public static func arrange(_ ids: [UUID], by stored: [UUID]) -> [UUID] {
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var result = stored.filter { rank[$0] != nil && seen.insert($0).inserted }
        for id in ids where !seen.contains(id) {
            let i = result.firstIndex { rank[$0]! > rank[id]! } ?? result.endIndex
            result.insert(id, at: i)
        }
        return result
    }

    /// Moves the course at `source` in `term`'s shown order to sit before `destination` (`count` for the end), as a
    /// list's drag reports it within that term. The other terms' entries stay as they were.
    public mutating func move(_ shown: [UUID], from source: Int, to destination: Int) {
        guard shown.indices.contains(source) else { return }
        var order = shown
        let id = order.remove(at: source)
        let to = min(max(destination, 0), shown.count)
        order.insert(id, at: to > source ? to - 1 : to)
        courses = courses.filter { !shown.contains($0) } + order
    }
}
