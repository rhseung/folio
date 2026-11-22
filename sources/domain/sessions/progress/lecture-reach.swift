import Foundation

// 렉처 하나를 어느 쪽까지 배웠는지다. `explicit`은 진도 쪽에서 읽었다는 뜻이고, 아니면 회차에 연결한 단원이나 렉처
// 전체로 짐작한 값이다.
public struct LectureReach: Equatable, Sendable {
    public var page: Int
    public var explicit: Bool

    public init(page: Int, explicit: Bool) {
        self.page = page
        self.explicit = explicit
    }

    public static let none = LectureReach(page: 0, explicit: false)
    public static let whole = LectureReach(page: .max, explicit: false)

    public var isWhole: Bool { page == .max }
}

extension CourseFile {
    // 진도 쪽이 빈 지난 회차는 채우지 않고 마지막 진도 쪽 앞을 모두 배운 것으로 센다. 진도 쪽이 하나도 없으면 그
    // 렉처를 쓴 회차들의 단원 쪽 구간까지, 그 회차들에 단원도 없으면 렉처 전체를 배운 것으로 본다.
    public func reach(of material: UUID, before date: Date? = nil) -> LectureReach {
        let held = sessions.filter { s in !s.isCancelled && date.map { s.date < $0 } ?? true }
        let links = held.compactMap { s in s.materials.first { $0.materialId == material }.map { (session: s, link: $0) } }
        guard !links.isEmpty else { return .none }
        if let last = links.compactMap(\.link.pages?.upperBound).max() { return LectureReach(page: last, explicit: true) }
        let pages = links.flatMap { units(of: $0.session) }.flatMap(\.lecturePages).filter { $0.materialId == material }
        return pages.map(\.pages.upperBound).max().map { LectureReach(page: $0, explicit: false) } ?? .whole
    }

    public func isTaught(_ unit: Unit, before date: Date? = nil) -> Bool {
        let held = sessions.filter { s in !s.isCancelled && date.map { s.date < $0 } ?? true }
        if held.contains(where: { unitIds(of: $0).contains(unit.id) }) { return true }
        return unit.lecturePages.contains { p in
            let reach = reach(of: p.materialId, before: date)
            return reach.page > 0 && Self.covers(1...reach.page, unit: p.pages)
        }
    }
}
