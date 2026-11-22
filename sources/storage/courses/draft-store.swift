import FolioDomain
import Foundation

extension StudyDraft: StoredModel {
    public static let schemaVersion = 1
}

extension CourseStore {
    var draftsURL: URL { metadataURL.appending(path: StandardLayout.draftsFolder) }

    public func drafts() throws -> [StoredDocument<StudyDraft>] {
        guard FileManager.default.fileExists(atPath: draftsURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: draftsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try StoredDocument<StudyDraft>.read(from: $0) }
            .sorted { $0.model.createdAt > $1.model.createdAt }
    }

    public func save(_ draft: StoredDocument<StudyDraft>) throws {
        try draft.write(to: draftsURL.appending(path: "\(draft.model.id.uuidString).json"))
    }

    public func discard(draft id: UUID) throws {
        let url = draftsURL.appending(path: "\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try CoordinatedFile.trash(url)
    }
}
