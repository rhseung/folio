import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension ActionContext {
    // 문제 초안은 자료마다 하나다. 사용자가 파일마다 받으므로 같은 자료를 다시 뽑으면 앞의 초안을 바꾼다.
    func problemDraft(_ course: UUID, material: UUID) throws -> StudyDraft? {
        try store(course).drafts().map(\.model).first { $0.kind == .problems && $0.materialId == material && !$0.isApplied }
    }

    func saveDraft(_ course: UUID, _ draft: StudyDraft, replacing old: StudyDraft?) throws {
        let store = try store(course)
        if let old, old.id != draft.id { try discardDraft(course, old.id) }
        let url = store.draftURL(draft.id)
        let exists = FileManager.default.fileExists(atPath: url.path)
        _ = try io(Change(exists ? .changed : .added, relative(url))) { try store.save(StoredDocument(new: draft)) }
    }

    func discardDraft(_ course: UUID, _ id: UUID) throws {
        let store = try store(course)
        _ = try io(Change(.removed, relative(store.draftURL(id)))) { try store.discard(draft: id) }
    }

    func requireProblemDraft(_ course: UUID, material: UUID) throws -> StudyDraft {
        guard let draft = try problemDraft(course, material: material) else {
            throw ActionError.notFound(String(localized: .errorNotFoundProblemDraft(name(of: material) ?? material.uuidString)))
        }
        return draft
    }
}
