import Foundation

public enum MaterialTarget: Hashable, Sendable {
    case session(UUID)
    case unit(UUID)
    case exam(UUID)
}

public enum MaterialRoute: Hashable, Sendable {
    case direct
    case pages
    case session(UUID)
    case unit(UUID)
    case folder
}

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

    public func units(of material: Material) -> [(unit: Unit, routes: [MaterialRoute])] {
        UnitTree.outline(units).compactMap { row in
            let routes = routes(of: material, to: .unit(row.unit.id))
            return routes.isEmpty ? nil : (row.unit, routes)
        }
    }

    private func holds(unit id: UUID, _ material: UUID) -> Bool {
        units.contains { $0.id == id && $0.lecturePages.contains { $0.materialId == material } }
    }

    func sessions(inUnit id: UUID) -> [Session] {
        sessions.filter { s in s.unitIds.contains(id) || units.contains { $0.id == id && $0.sessionIds.contains(s.id) } }.sorted(
            by: Session.inOrder)
    }

    func unitsCovering(session id: UUID) -> [UUID] {
        let session = sessions.first { $0.id == id }
        let direct = UnitTree.outline(units).map(\.unit).filter { $0.sessionIds.contains(id) || session?.unitIds.contains($0.id) == true }
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
