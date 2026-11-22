import Foundation

public enum UnitTree {
    public static func outline(_ units: [Unit]) -> [(unit: Unit, depth: Int)] {
        var result: [(unit: Unit, depth: Int)] = []
        var seen: Set<UUID> = []
        let children = Dictionary(grouping: units) { parent(of: $0, in: units) }
        func walk(_ unit: Unit, _ depth: Int) {
            guard seen.insert(unit.id).inserted else { return }
            result.append((unit, depth))
            for child in sorted(children[unit.id] ?? []) { walk(child, depth + 1) }
        }
        for root in sorted(children[nil] ?? []) { walk(root, 0) }
        for unit in sorted(units) where !seen.contains(unit.id) { walk(unit, 0) }
        return result
    }

    public static func subtree(of id: UUID, in units: [Unit]) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for u in units where u.parentId == next && result.insert(u.id).inserted { frontier.append(u.id) }
        }
        return result
    }

    public static func deepest(_ picked: [Unit], in units: [Unit]) -> [Unit] {
        let ids = Set(picked.map(\.id))
        return picked.filter { subtree(of: $0.id, in: units).subtracting([$0.id]).isDisjoint(with: ids) }
    }

    public static func parentChoices(for id: UUID, in units: [Unit]) -> [Unit] {
        let excluded = subtree(of: id, in: units)
        return outline(units).map(\.unit).filter { !excluded.contains($0.id) }
    }

    @discardableResult
    public static func move(_ id: UUID, by offset: Int, in units: inout [Unit]) -> Bool {
        guard let unit = units.first(where: { $0.id == id }) else { return false }
        let parent = parent(of: unit, in: units)
        var siblings = sorted(units.filter { self.parent(of: $0, in: units) == parent }).map(\.id)
        guard let from = siblings.firstIndex(of: id), siblings.indices.contains(from + offset) else { return false }
        siblings.swapAt(from, from + offset)
        for (rank, sibling) in siblings.enumerated() {
            if let i = units.firstIndex(where: { $0.id == sibling }) { units[i].order = rank + 1 }
        }
        return true
    }

    @discardableResult
    public static func setParent(_ id: UUID, to parent: UUID?, in units: inout [Unit]) -> Bool {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return false }
        if let parent, subtree(of: id, in: units).contains(parent) || !units.contains(where: { $0.id == parent }) { return false }
        units[i].parentId = parent
        units[i].order = nextOrder(under: parent, in: units.filter { $0.id != id })
        return true
    }

    public static func nextOrder(under parent: UUID?, in units: [Unit]) -> Int {
        (units.filter { self.parent(of: $0, in: units) == parent }.map(\.order).max() ?? 0) + 1
    }

    static func parent(of unit: Unit, in units: [Unit]) -> UUID? {
        unit.parentId.flatMap { p in p != unit.id && units.contains { $0.id == p } ? p : nil }
    }

    static func sorted(_ units: [Unit]) -> [Unit] {
        units.sorted { ($0.order, $0.title, $0.id.uuidString) < ($1.order, $1.title, $1.id.uuidString) }
    }
}

extension CourseFile {
    // 시험 범위도 계산값과 다른 단원만 저장한다. 그래서 고친 범위가 계산값과 같아지면 아무것도 남지 않는다.
    public mutating func setScope(_ unitIds: [UUID], exam: UUID) {
        guard let e = exams.firstIndex(where: { $0.id == exam }) else { return }
        let wanted = Set(unitIds).intersection(units.map(\.id))
        let computed = Set(computedScope(of: exams[e]) ?? [])
        let order = UnitTree.outline(units).map(\.unit.id)
        exams[e].addedScopeUnitIds = order.filter { wanted.contains($0) && !computed.contains($0) }
        exams[e].removedScopeUnitIds = order.filter { computed.contains($0) && !wanted.contains($0) }
    }

    public mutating func toggle(exam: UUID, unit: UUID) {
        guard units.contains(where: { $0.id == unit }), let e = exams.first(where: { $0.id == exam }) else { return }
        let group = UnitTree.subtree(of: unit, in: units)
        var scope = Set(scope(of: e))
        if scope.contains(unit) { scope.subtract(group) } else { scope.formUnion(group) }
        setScope(Array(scope), exam: exam)
    }

    @discardableResult
    public mutating func addScope(_ unitIds: [UUID], exam: UUID) -> [UUID] {
        guard let e = exams.first(where: { $0.id == exam }) else { return [] }
        let had = scope(of: e)
        // 고른 단원만 넣는다. 장이 범위에 들어도 수업에서 건너뛴 절은 빠진다.
        let added = unitIds.filter { id in !had.contains(id) && units.contains { $0.id == id } }
        setScope(had + added, exam: exam)
        return added
    }

    public mutating func resetScope(exam: UUID) {
        guard let e = exams.firstIndex(where: { $0.id == exam }) else { return }
        exams[e].addedScopeUnitIds = []
        exams[e].removedScopeUnitIds = []
    }
}

extension CourseFile {
    public func unit(ofNote id: UUID) -> UUID? {
        guard let entry = notes.first(where: { $0.id == id }) else { return nil }
        let known = Set(units.map(\.id))
        return meta(of: entry).unitIds.first(where: known.contains)
    }

    public func unitForNewCard(viewing unit: UUID?, note: UUID?) -> UUID? {
        if let unit, units.contains(where: { $0.id == unit }) { return unit }
        return note.flatMap(unit(ofNote:)) ?? UnitTree.outline(units).first?.unit.id
    }
}
