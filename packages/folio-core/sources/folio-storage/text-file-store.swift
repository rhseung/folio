import FolioDomain
import Foundation

extension CourseStore {
    public func readText(_ coursePath: String) throws -> String {
        guard let text = String(data: try CoordinatedFile.read(fileURL(coursePath)), encoding: .utf8) else { throw StorageError.notUTF8(coursePath) }
        return text
    }

    public func writeText(_ coursePath: String, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: fileURL(coursePath))
    }

    /// Replaces a file the app made itself, such as a build's PDF. Never used for files the user brought in.
    /// `keepOld` sends the file there to the Trash first, where the user can still take it back.
    public func replaceFile(_ coursePath: String, with source: URL, keepOld: Bool = false) throws {
        let data = try Data(contentsOf: source)
        if keepOld, FileManager.default.fileExists(atPath: fileURL(coursePath).path) { try CoordinatedFile.trash(fileURL(coursePath)) }
        try CoordinatedFile.write(data, to: fileURL(coursePath))
    }

    /// Nil when iCloud hasn't downloaded the file yet.
    public func hash(_ coursePath: String) throws -> String? {
        try FileHash.sha256(of: fileURL(coursePath))
    }

    /// Takes the size and hash of a file just written in place. `refreshMaterials` only rehashes a file whose size
    /// changed, so an edit that keeps the length would leave the old hash behind.
    public func rehash(_ material: UUID, in file: inout CourseFile, device: DeviceID, now: Date) throws {
        guard let i = file.materials.firstIndex(where: { $0.id == material }) else { return }
        let url = fileURL(file.materials[i].path)
        let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let hash = try FileHash.sha256(of: url)
        guard file.materials[i].size != size || file.materials[i].hash != hash else { return }
        file.materials[i].size = size
        file.materials[i].hash = hash
        file.materials[i].touch(by: device, at: now)
    }
}
