import FolioDomain
import Foundation

extension CourseStore {
    public func readText(_ coursePath: String) throws -> String {
        guard let text = String(data: try CoordinatedFile.read(fileURL(coursePath)), encoding: .utf8) else {
            throw StorageError.notUTF8(coursePath)
        }
        return text
    }

    public func writeText(_ coursePath: String, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: fileURL(coursePath))
    }

    public func createText(_ coursePath: String, text: String) throws {
        try CoordinatedFile.create(Data(text.utf8), at: fileURL(coursePath))
    }

    public func codeProject(containing folder: String) -> String? {
        let parts = folder.split(separator: "/").map(String.init)
        for n in parts.indices {
            let path = parts[...n].joined(separator: "/")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: fileURL(path).path) else { return nil }
            if IndexRules.isCodeProject(childNames: names) { return path }
        }
        return nil
    }

    public func replaceFile(_ coursePath: String, with source: URL, keepOld: Bool = false) throws {
        let data = try Data(contentsOf: source)
        if keepOld, FileManager.default.fileExists(atPath: fileURL(coursePath).path) { try CoordinatedFile.trash(fileURL(coursePath)) }
        try CoordinatedFile.write(data, to: fileURL(coursePath))
    }

    public func hash(_ coursePath: String) throws -> String? {
        try FileHash.sha256(of: fileURL(coursePath))
    }

    // `refreshMaterials`는 크기가 바뀐 파일만 다시 해시하므로, 길이가 같은 편집은 옛 해시를 남긴다.
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
