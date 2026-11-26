import Foundation

// 다음 시험 범위 밖의 단원을 묶은 것이다. 단원 페이지의 "그 밖의 단원"이 펼치면 이 차례로 소제목을 둔다.
public struct UnitGroup: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case exam(UUID)
        case untested
        case untaught
    }

    public var kind: Kind
    public var unitIds: [UUID]

    public init(kind: Kind, unitIds: [UUID]) {
        self.kind = kind
        self.unitIds = unitIds
    }
}

extension CourseFile {
    // 단원은 그 단원이 든 가장 최근 지난 시험 하나에만 들어간다. 지난 시험 어디에도 없는 단원은 지금까지 배운 것과
    // 아직 안 배운 것으로 나눈다. 장처럼 쪽 구간이 없는 상위 단원은 하위 단원 하나라도 배웠으면 배운 것이다.
    public func unitGroups(besides exam: Exam, now: Date) -> [UnitGroup] {
        let outline = UnitTree.outline(units).map(\.unit)
        let inScope = Set(scope(of: exam, outline: outline))
        let rest = outline.filter { !inScope.contains($0.id) }
        let start = exam.start ?? .distantFuture
        let past = exams.filter { e in e.id != exam.id && e.start.map { $0 < start } ?? false }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
        let pastScopes = past.map { (exam: $0, ids: Set(scope(of: $0, outline: outline))) }
        let taught = Set(outline.filter { isTaught($0, before: now) }.map(\.id))

        var groups: [UnitGroup.Kind: [UUID]] = [:]
        for unit in rest {
            let kind: UnitGroup.Kind =
                if let e = pastScopes.first(where: { $0.ids.contains(unit.id) }) {
                    .exam(e.exam.id)
                } else if !UnitTree.subtree(of: unit.id, in: units).isDisjoint(with: taught) {
                    .untested
                } else {
                    .untaught
                }
            groups[kind, default: []].append(unit.id)
        }
        let order = past.map { UnitGroup.Kind.exam($0.id) } + [.untested, .untaught]
        return order.compactMap { kind in groups[kind].map { UnitGroup(kind: kind, unitIds: $0) } }
    }
}
