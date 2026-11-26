import Foundation

extension CourseFile {
    // 나누기는 쪽만 기록하므로 `unitIds`만 읽으면 나눈 렉처가 자기 단원에서 빠진다.
    public func routes(of material: Material, to target: MaterialTarget) -> [MaterialRoute] {
        switch target {
        case .session(let id):
            let direct =
                material.sessionIds.contains(id)
                || sessions.contains { $0.id == id && $0.materials.contains { $0.materialId == material.id } }
            let units = unitsCovering(session: id).filter { material.unitIds.contains($0) || holds(unit: $0, material.id) }
            return (direct ? [.direct] : []) + units.map(MaterialRoute.unit)
        case .unit(let id):
            let direct = material.unitIds.contains(id)
            let via = sessions(inUnit: id).filter { s in s.materials.contains { $0.materialId == material.id } }.map {
                MaterialRoute.session($0.id)
            }
            return (direct ? [.direct] : []) + (holds(unit: id, material.id) ? [.pages] : []) + via
        case .exam(let id):
            guard let exam = exams.first(where: { $0.id == id }) else { return [] }
            let inFolder = MaterialIntake.folder(of: exam).map { material.path.hasPrefix($0 + "/") } == true
            return (material.examIds.contains(id) ? [.direct] : []) + (inFolder ? [.folder] : [])
        }
    }

    public func materials(of target: MaterialTarget) -> [(material: Material, routes: [MaterialRoute])] {
        materials.compactMap { m in
            let routes = routes(of: m, to: target)
            return routes.isEmpty ? nil : (m, routes)
        }
    }

    // `routes(of:to: .unit)`와 같은 답을 낸다. 단원마다 그 함수를 부르면 단원마다 단원 순서를 다시 만들고 모든 회차의 단원을
    // 다시 계산한다. 자료 목록은 행마다 이것을 부르므로 자료 수 × 단원 수의 제곱 × 회차 수만큼 돌아, 자료 페이지를 여는 데
    // 1~2초가 걸렸다. 그래서 단원 순서는 한 번만 만들고, 이 자료가 든 회차의 단원만 한 번씩 계산한다.
    public func units(of material: Material) -> [(unit: Unit, routes: [MaterialRoute])] {
        let outline = UnitTree.outline(units).map(\.unit)
        let held = Set(units.filter { $0.lecturePages.contains { $0.materialId == material.id } }.map(\.id))
        let taught = sessions.sorted(by: Session.inOrder).filter { s in s.materials.contains { $0.materialId == material.id } }
            .map { (id: $0.id, units: Set(unitIds(of: $0, outline: outline))) }
        return outline.compactMap { unit -> (unit: Unit, routes: [MaterialRoute])? in
            var routes: [MaterialRoute] = []
            if material.unitIds.contains(unit.id) { routes.append(.direct) }
            if held.contains(unit.id) { routes.append(.pages) }
            for s in taught where s.units.contains(unit.id) { routes.append(.session(s.id)) }
            return routes.isEmpty ? nil : (unit, routes)
        }
    }

    private func holds(unit id: UUID, _ material: UUID) -> Bool {
        units.contains { $0.id == id && $0.lecturePages.contains { $0.materialId == material } }
    }

    func sessions(inUnit id: UUID) -> [Session] {
        sessions(of: id)
    }

    func unitsCovering(session id: UUID) -> [UUID] {
        let direct = sessions.first { $0.id == id }.map { units(of: $0) } ?? []
        var seen = Set(direct.map(\.id)), chain = direct.map(\.id)
        var next = direct.compactMap(\.parentId)
        while let parent = next.popLast() {
            guard seen.insert(parent).inserted, let unit = units.first(where: { $0.id == parent }) else { continue }
            chain.append(parent)
            if let up = unit.parentId { next.append(up) }
        }
        return chain
    }
}
