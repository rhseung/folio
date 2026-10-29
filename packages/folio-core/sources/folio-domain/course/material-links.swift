import Algorithms
import Foundation

/// `material_view` log event: the page a PDF was left at. Kept in the per-device log rather than a shared file
/// because it changes on every reading; the newest event across devices wins, so the iPad resumes where the Mac stopped.
public struct MaterialViewEvent: LogEvent, Equatable {
    public static let type = "material_view"
    public var materialId: UUID
    /// 0-based page index.
    public var page: Int

    public init(materialId: UUID, page: Int) {
        self.materialId = materialId
        self.page = page
    }
}

extension CourseFile {
    /// Links a material to a session or changes its page range. The pages live in `Session.materials`;
    /// `Material.sessionIds` mirrors the link so either side can be read alone.
    public mutating func linkMaterial(_ material: UUID, session: UUID, firstPage: Int? = nil, lastPage: Int? = nil) {
        guard let m = materials.firstIndex(where: { $0.id == material }), let s = sessions.firstIndex(where: { $0.id == session }) else { return }
        let link = SessionMaterial(materialId: material, firstPage: firstPage, lastPage: lastPage)
        if let i = sessions[s].materials.firstIndex(where: { $0.materialId == material }) {
            sessions[s].materials[i] = link
        } else {
            sessions[s].materials.append(link)
        }
        if !materials[m].sessionIds.contains(session) { materials[m].sessionIds.append(session) }
    }

    public mutating func unlinkMaterial(_ material: UUID, session: UUID) {
        for s in sessions.indices where sessions[s].id == session { sessions[s].materials.removeAll { $0.materialId == material } }
        for m in materials.indices where materials[m].id == material { materials[m].sessionIds.removeAll { $0 == session } }
    }

    public mutating func setMaterial(_ material: UUID, unit: UUID, linked: Bool) {
        guard let m = materials.firstIndex(where: { $0.id == material }) else { return }
        materials[m].unitIds.removeAll { $0 == unit }
        if linked { materials[m].unitIds.append(unit) }
    }

    public func sessionLinks(of material: UUID) -> [(session: Session, link: SessionMaterial)] {
        sessions.sorted { ($0.week, $0.index) < ($1.week, $1.index) }
            .compactMap { s in s.materials.first { $0.materialId == material }.map { (s, $0) } }
    }

    /// Points a material at a file the user picked (docs/SPEC.md "파일 추적": "다른 파일을 지정").
    /// A refresh usually registered that file as a new material when the original went missing; that duplicate
    /// is dropped and everything that referred to it is moved here, so the user's links survive under the original ID.
    public mutating func relinkMaterial(_ id: UUID, to path: String, hash: String?, size: Int64?, bookmark: Data?, device: DeviceID, now: Date) {
        guard materials.contains(where: { $0.id == id }) else { return }
        if let dup = materials.first(where: { $0.path == path && $0.id != id }) {
            merge(dup, into: id)
        }
        guard let i = materials.firstIndex(where: { $0.id == id }) else { return }
        let role = MaterialTracking.role(for: path, overrides: course.folderRoles) ?? materials[i].role
        materials[i].path = path
        materials[i].isFolder = false
        materials[i].hash = hash
        materials[i].size = size
        materials[i].bookmark = bookmark
        materials[i].role = role
        materials[i].status = role == nil ? .unclassified : .classified
        materials[i].touch(by: device, at: now)
    }

    private mutating func merge(_ dup: Material, into id: UUID) {
        func swap(_ old: UUID?) -> UUID? { old == dup.id ? id : old }
        materials.removeAll { $0.id == dup.id }
        for m in materials.indices {
            materials[m].sourceOf = swap(materials[m].sourceOf)
            materials[m].solutionOf = swap(materials[m].solutionOf)
            if materials[m].id == id {
                materials[m].sessionIds += dup.sessionIds.filter { !materials[m].sessionIds.contains($0) }
                materials[m].unitIds += dup.unitIds.filter { !materials[m].unitIds.contains($0) }
                materials[m].kind = materials[m].kind ?? dup.kind
            }
        }
        for s in sessions.indices {
            sessions[s].materials = sessions[s].materials
                .map { SessionMaterial(materialId: swap($0.materialId)!, firstPage: $0.firstPage, lastPage: $0.lastPage) }
                .uniqued(on: \.materialId)
        }
        for a in assignments.indices {
            assignments[a].problemMaterialId = swap(assignments[a].problemMaterialId)
            assignments[a].submissionMaterialIds = Array(assignments[a].submissionMaterialIds.map { swap($0)! }.uniqued())
        }
        course.syllabusMaterialId = swap(course.syllabusMaterialId)
    }
}
