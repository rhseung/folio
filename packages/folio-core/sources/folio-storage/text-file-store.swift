import FolioDomain
import Foundation

extension CourseStore {
    public func readText(_ coursePath: String) throws -> String {
        String(decoding: try CoordinatedFile.read(fileURL(coursePath)), as: UTF8.self)
    }

    public func writeText(_ coursePath: String, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: fileURL(coursePath))
    }

    /// Replaces a file the app made itself, such as a build's PDF. Never used for files the user brought in.
    public func replaceFile(_ coursePath: String, with source: URL) throws {
        try CoordinatedFile.write(try Data(contentsOf: source), to: fileURL(coursePath))
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
