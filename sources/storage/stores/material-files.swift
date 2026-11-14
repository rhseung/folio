import FolioDomain
import Foundation

public enum MaterialFileError: Error, Equatable {
    case outsideCourseFolder(String)
}

extension CourseStore {
    public func download(_ material: Material) throws -> URL {
        let file = url.appending(path: material.path)
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { _ in }
        if let error { throw error }
        return file
    }

    public func relink(_ id: UUID, to picked: URL, in file: inout CourseFile, device: DeviceID, now: Date) throws {
        guard let path = coursePath(of: picked) else { throw MaterialFileError.outsideCourseFolder(picked.lastPathComponent) }
        let size = try picked.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        file.relinkMaterial(
            id, to: path, hash: try FileHash.sha256(of: picked), size: size,
            bookmark: try? picked.bookmarkData(), device: device, now: now
        )
    }
}

extension CourseStore {
    public func contains(_ coursePath: String) -> Bool {
        let (root, path) = (url.standardizedFileURL.path, fileURL(coursePath).standardizedFileURL.path)
        return path == root || path.hasPrefix(root + "/")
    }

    public func coursePath(of file: URL) -> String? {
        // 고른 URL과 GIST URL은 `/private`(임시 폴더)나 별칭만큼 다를 수 있으므로 양쪽의 심볼릭 링크를 푼다.
        let root = url.resolvingSymlinksInPath().path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = file.resolvingSymlinksInPath().path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return target.hasPrefix(root + "/") ? String(target.dropFirst(root.count + 1)) : nil
    }

    public func importFile(_ source: URL, into folder: String, name: String? = nil) throws -> String {
        let dir = url.appending(path: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = MaterialIntake.freeName(name ?? source.lastPathComponent, taken: names(in: folder))
        try CoordinatedFile.copy(source, to: dir.appending(path: fileName))
        return "\(folder)/\(fileName)"
    }

    public func names(in folder: String) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: url.appending(path: folder).path)) ?? [])
    }

    public func move(_ id: UUID, to newPath: String, gist: URL, in file: inout CourseFile, device: DeviceID, now: Date) throws -> UUID {
        guard let m = file.materials.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let root = gist.standardizedFileURL.path
        let prefix = String(url.standardizedFileURL.path.dropFirst(root.count + 1)) + "/"
        let batch = try MoveJournal.apply([PlannedMove(from: prefix + m.path, to: prefix + newPath)], in: gist, device: device, now: now)
        file.relinkMaterial(
            id, to: newPath, hash: m.hash, size: m.size, bookmark: try? fileURL(newPath).bookmarkData(), device: device, now: now)
        return batch
    }

    public func trash(_ id: UUID, in file: inout CourseFile) throws {
        guard let m = file.materials.first(where: { $0.id == id }) else { return }
        try CoordinatedFile.trash(fileURL(m.path))
        try file.remove(Material.self, id)
    }
}
