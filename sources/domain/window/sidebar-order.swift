import Foundation

public struct SidebarOrder: Codable, Sendable, Equatable {
    public var courses: [UUID]

    public init(courses: [UUID] = []) {
        self.courses = courses
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        courses = try c.value(.courses, or: [])
    }

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

    // `destination`은 목록의 드래그가 알려 주는 값 그대로이고, 끝이면 `count`이다.
    public mutating func move(_ shown: [UUID], from source: Int, to destination: Int) {
        guard shown.indices.contains(source) else { return }
        var order = shown
        let id = order.remove(at: source)
        let to = min(max(destination, 0), shown.count)
        order.insert(id, at: to > source ? to - 1 : to)
        courses = courses.filter { !shown.contains($0) } + order
    }
}
