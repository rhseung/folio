import Foundation

extension CourseFile {
    // 경계 쪽 하나만 겹치면 넣지 않는다. 한 수업의 끝 쪽이 다음 단원의 첫 쪽(장 제목 쪽)이거나 앞 단원의 마지막 쪽에서
    // 시작하는 일이 흔해서, 그 쪽 하나로 단원을 넣으면 배우지 않은 단원이 회차와 시험 범위에 들어온다. 한 쪽짜리 단원과
    // 한 쪽만 다룬 수업은 그 한 쪽이 전부이므로 넣는다.
    public static func covers(_ progress: ClosedRange<Int>, unit pages: ClosedRange<Int>) -> Bool {
        guard progress.overlaps(pages) else { return false }
        let shared = progress.clamped(to: pages)
        return shared.upperBound > shared.lowerBound || pages.lowerBound == pages.upperBound || progress.lowerBound == progress.upperBound
    }

    public func computedUnitIds(of session: Session) -> [UUID] {
        computedUnitIds(of: session, outline: UnitTree.outline(units).map(\.unit))
    }

    // 단원 순서는 부르는 쪽이 한 번 만들어 넘긴다. 노트와 회차 표가 회차마다, 단원마다 순서를 다시 만들면 단원 수의 제곱이
    // 넘게 늘어서, 단원 69개인 과목에서 노트 목록 하나를 읽는 데 Release로 0.7초가 걸렸다.
    func computedUnitIds(of session: Session, outline: [Unit]) -> [UUID] {
        guard !session.isCancelled else { return [] }
        let taught = session.materials.compactMap { m in m.pages.map { (material: m.materialId, pages: $0) } }
        guard !taught.isEmpty else { return [] }
        return outline.filter { u in
            u.lecturePages.contains { held in taught.contains { $0.material == held.materialId && Self.covers($0.pages, unit: held.pages) }
            }
        }.map(\.id)
    }

    public func unitIds(of session: Session) -> [UUID] {
        unitIds(of: session, outline: UnitTree.outline(units).map(\.unit))
    }

    func unitIds(of session: Session, outline: [Unit]) -> [UUID] {
        let computed = Set(computedUnitIds(of: session, outline: outline))
        let added = Set(session.addedUnitIds)
        let removed = Set(session.removedUnitIds)
        return outline.map(\.id).filter { (computed.contains($0) || added.contains($0)) && !removed.contains($0) }
    }

    public func units(of session: Session) -> [Unit] {
        let outline = UnitTree.outline(units).map(\.unit)
        let ids = Set(unitIds(of: session, outline: outline))
        return outline.filter { ids.contains($0.id) }
    }

    public func sessions(of unit: UUID) -> [Session] {
        let outline = UnitTree.outline(units).map(\.unit)
        return sessions.filter { unitIds(of: $0, outline: outline).contains(unit) }.sorted(by: Session.inOrder)
    }

    public func isLinked(session: UUID, unit: UUID) -> Bool {
        sessions.first { $0.id == session }.map { unitIds(of: $0).contains(unit) } ?? false
    }

    // 계산값과 같은 단원은 저장하지 않는다. 그래서 고른 단원이 계산값과 같아지면 더한 단원과 뺀 단원이 모두 빈다.
    public mutating func setUnits(_ ids: [UUID], session: UUID) {
        guard let s = sessions.firstIndex(where: { $0.id == session }) else { return }
        let known = Set(units.map(\.id))
        let wanted = Set(ids).intersection(known)
        let computed = Set(computedUnitIds(of: sessions[s]))
        let order = UnitTree.outline(units).map(\.unit.id)
        sessions[s].addedUnitIds = order.filter { wanted.contains($0) && !computed.contains($0) }
        sessions[s].removedUnitIds = order.filter { computed.contains($0) && !wanted.contains($0) }
    }

    public mutating func toggle(session: UUID, unit: UUID) {
        guard units.contains(where: { $0.id == unit }), let s = sessions.first(where: { $0.id == session }) else { return }
        var ids = unitIds(of: s)
        if let i = ids.firstIndex(of: unit) { ids.remove(at: i) } else { ids.append(unit) }
        setUnits(ids, session: session)
    }
}
