import FolioDomain
import Foundation

public enum MaterialFileError: Error, Equatable {
    /// Picked files must already be in the course folder: bringing one in is a move, which needs the cleanup's approval flow.
    case outsideCourseFolder(String)
}

extension CourseStore {
    /// The material's file, downloaded from iCloud first if needed (a coordinated read waits for the download).
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
    /// Lexical, since a planned path may not exist yet.
    public func contains(_ coursePath: String) -> Bool {
        let (root, path) = (url.standardizedFileURL.path, fileURL(coursePath).standardizedFileURL.path)
        return path == root || path.hasPrefix(root + "/")
    }

    public func coursePath(of file: URL) -> String? {
        // Resolve symlinks on both sides: picked URLs and the GIST URL can differ by `/private` (temp folders) or aliases.
        let root = url.resolvingSymlinksInPath().path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = file.resolvingSymlinksInPath().path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return target.hasPrefix(root + "/") ? String(target.dropFirst(root.count + 1)) : nil
    }

    /// Copies a file from outside into `folder` (course-relative) and returns its path. A taken name gets ` 2`, so nothing
    /// is overwritten. Copying in leaves the original where it was, so unlike a move it needs no approval.
    public func importFile(_ source: URL, into folder: String, name: String? = nil) throws -> String {
        let dir = url.appending(path: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fileName = MaterialIntake.freeName(name ?? source.lastPathComponent, taken: taken)
        try CoordinatedFile.copy(source, to: dir.appending(path: fileName))
        return "\(folder)/\(fileName)"
    }

    /// Moves or renames a tracked file through `moves.jsonl`, so it can be undone, keeping its ID and links.
    public func move(_ id: UUID, to newPath: String, gist: URL, in file: inout CourseFile, device: DeviceID, now: Date) throws -> UUID {
        guard let m = file.materials.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let root = gist.standardizedFileURL.path
        let prefix = String(url.standardizedFileURL.path.dropFirst(root.count + 1)) + "/"
        let batch = try MoveJournal.apply([PlannedMove(from: prefix + m.path, to: prefix + newPath)], in: gist, device: device, now: now)
        file.relinkMaterial(id, to: newPath, hash: m.hash, size: m.size, bookmark: try? fileURL(newPath).bookmarkData(), device: device, now: now)
        return batch
    }

    /// Moves a tracked file to the Trash, where the user can still put it back, and stops tracking it.
    /// Links to it stay, as with disconnecting (docs/SPEC.md "파일 추적").
    public func trash(_ id: UUID, in file: inout CourseFile) throws {
        guard let m = file.materials.first(where: { $0.id == id }) else { return }
        try CoordinatedFile.trash(fileURL(m.path))
        file.materials.removeAll { $0.id == id }
    }
}
