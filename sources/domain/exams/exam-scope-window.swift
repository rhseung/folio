import Foundation

extension CourseFile {
    public func previousExam(before exam: Exam) -> Exam? {
        guard let start = exam.start else { return nil }
        return exams.filter { e in e.id != exam.id && e.start.map { $0 < start } ?? false }.max {
            ($0.start ?? .distantPast) < ($1.start ?? .distantPast)
        }
    }

    // 지난 시험 이후 배운 단원이다. 지난 시험 전에 시작해 그 뒤에도 이어 배운 단원도 넣는다. 날짜가 없는 시험은
    // 언제까지 배운 것인지 몰라 계산하지 않는다.
    public func computedScope(of exam: Exam) -> [UUID]? {
        computedScope(of: exam, outline: UnitTree.outline(units).map(\.unit))
    }

    func computedScope(of exam: Exam, outline: [Unit]) -> [UUID]? {
        guard let end = exam.start else { return nil }
        let from = previousExam(before: exam)?.start
        let window = sessions.filter { s in !s.isCancelled && s.date < end && from.map { s.date >= $0 } ?? true }
        var ids = Set(window.flatMap { unitIds(of: $0, outline: outline) })

        var reaches: [UUID: (from: Int, to: Int)] = [:]
        for material in Set(units.flatMap(\.lecturePages).map(\.materialId)) {
            let to = reach(of: material, before: end)
            guard to.page > 0 else { continue }
            var start = from.map { reach(of: material, before: $0) } ?? .none
            // 지난 시험 전 진도를 짐작으로만 알면, 그 뒤에 적은 첫 진도 쪽 앞까지를 지난 시험 전에 배운 것으로 본다. 진도
            // 쪽은 이전 수업이 끝난 다음 쪽에서 시작하므로, 진도를 적지 않은 지난 수업들이 그 앞을 가르쳤다.
            let taughtBefore = from.map { f in sessions.contains { !$0.isCancelled && $0.date < f } } ?? false
            if !start.explicit, start.page > 0 || taughtBefore,
                let next = window.compactMap({ s in s.materials.first { $0.materialId == material }?.pages?.lowerBound }).min()
            {
                start.page = start.page == 0 ? next - 1 : min(start.page, next - 1)
            }
            if to.page > start.page { reaches[material] = (start.page, to.page) }
        }
        for unit in units {
            let learned = unit.lecturePages.contains { p in
                reaches[p.materialId].map { r in Self.covers((r.from + 1)...r.to, unit: p.pages) } ?? false
            }
            if learned { ids.insert(unit.id) }
        }
        for id in Array(ids) { ids.formUnion(ancestors(of: id)) }
        return outline.map(\.id).filter(ids.contains)
    }

    public func scope(of exam: Exam) -> [UUID] {
        scope(of: exam, outline: UnitTree.outline(units).map(\.unit))
    }

    func scope(of exam: Exam, outline: [Unit]) -> [UUID] {
        let computed = Set(computedScope(of: exam, outline: outline) ?? [])
        let added = Set(exam.addedScopeUnitIds)
        let removed = Set(exam.removedScopeUnitIds)
        return outline.map(\.id).filter { (computed.contains($0) || added.contains($0)) && !removed.contains($0) }
    }

    public func scopeUnits(of exam: Exam) -> [Unit] {
        scopeUnits(of: exam, outline: UnitTree.outline(units).map(\.unit))
    }

    func scopeUnits(of exam: Exam, outline: [Unit]) -> [Unit] {
        let ids = Set(scope(of: exam, outline: outline))
        return outline.filter { ids.contains($0.id) }
    }

    public func exams(scoping unit: UUID) -> [Exam] {
        exams.filter { scope(of: $0).contains(unit) }
    }

    public func isEdited(scopeOf exam: Exam) -> Bool {
        !exam.addedScopeUnitIds.isEmpty || !exam.removedScopeUnitIds.isEmpty
    }

    func ancestors(of id: UUID) -> Set<UUID> {
        var out: Set<UUID> = []
        var parent = units.first { $0.id == id }?.parentId
        // 손으로 고친 JSON의 부모 순환에서 멈추도록 걸음 수를 제한한다.
        while let p = parent, out.count < units.count, out.insert(p).inserted {
            parent = units.first { $0.id == p }?.parentId
        }
        return out
    }
}
