import Foundation

public enum MaterialTarget: Hashable, Sendable {
    case session(UUID)
    case unit(UUID)
    case exam(UUID)
}

/// How a file reaches a target. Only `.direct` is a link the user can undo there; the others follow from links made
/// elsewhere, so a screen shows them apart.
public enum MaterialRoute: Hashable, Sendable {
    case direct
    /// The unit holds some of the file's pages (#321). Split, not linked: undone by changing the split, not here.
    case pages
    /// Through this session: it is linked to the unit and the file to the session.
    case session(UUID)
    /// Through this unit: the session sits in it, or under it, and the file is linked to the unit or holds its pages.
    case unit(UUID)
    /// It sits in the exam's own folder.
    case folder
}

extension CourseFile {
    /// The one rule for which files belong with a session, unit or exam; every screen and the transcription context
    /// ask it rather than walking the links themselves, so they cannot disagree.
    ///
    /// A session gathers its own files and those of its units and their parents: a chapter's slides cover every class
    /// in it. A unit gathers its own files and its sessions' files, not its parents': a whole chapter's slides would
    /// bury the few that cover one section. An exam gathers its folder's files and the ones linked to it.
    /// A unit holding some of a split lecture's pages counts as having the file: splitting writes only the pages, so
    /// reading `unitIds` alone would leave a split lecture off its own units.
    /// Empty when the file does not belong; `.direct` comes first, then `.pages`.
    public func routes(of material: Material, to target: MaterialTarget) -> [MaterialRoute] {
        switch target {
        case .session(let id):
            let direct = material.sessionIds.contains(id) || sessions.contains { $0.id == id && $0.materials.contains { $0.materialId == material.id } }
            let units = unitsCovering(session: id).filter { material.unitIds.contains($0) || holds(unit: $0, material.id) }
            return (direct ? [.direct] : []) + units.map(MaterialRoute.unit)
        case .unit(let id):
            let direct = material.unitIds.contains(id)
            let via = sessions(inUnit: id).filter { s in s.materials.contains { $0.materialId == material.id } }.map { MaterialRoute.session($0.id) }
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
        sessions.filter { s in s.unitIds.contains(id) || units.contains { $0.id == id && $0.sessionIds.contains(s.id) } }.sorted(by: Session.inOrder)
    }

    /// The session's units, then their parents up to the top, each once.
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
