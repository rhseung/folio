import FolioCore
import Foundation

enum CoordinatedFile {
    static func read(_ url: URL) throws -> Data {
        var error: NSError?
        var result: Result<Data, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = Result { try Data(contentsOf: url) }
        }
        return try finish(result, error)
    }

    static func write(_ data: Data, to url: URL) throws {
        try StagedFolder.guardWrite(url, detach: true)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        try finish(result, error)
    }

    // `write`는 덮어쓰므로, 먼저 확인하고 쓰면 그 사이에 다른 기기의 파일을 덮어쓸 틈이 생긴다. 그래서 옆에 먼저 쓴 뒤
    // 옮겨 넣는다.
    static func create(_ data: Data, at url: URL) throws {
        try StagedFolder.guardWrite(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { url in
            result = Result {
                let temp = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
                try data.write(to: temp)
                do { try FileManager.default.moveItem(at: temp, to: url) } catch {
                    try? FileManager.default.removeItem(at: temp)
                    throw error
                }
            }
        }
        try finish(result, error)
    }

    static func append(_ data: Data, to url: URL) throws {
        try StagedFolder.guardWrite(url, detach: true, keep: true)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { url in
            result = Result { try appendUncoordinated(data, to: url) }
        }
        try finish(result, error)
    }

    static func move(_ source: URL, to target: URL) throws {
        try StagedFolder.guardWrite(source)
        try StagedFolder.guardWrite(target)
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing, error: &error) {
            from, to in
            result = Result {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            }
        }
        try finish(result, error)
    }

    static func copy(_ source: URL, to target: URL) throws {
        try StagedFolder.guardWrite(target)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target, options: .forReplacing, error: &error) {
            from, to in
            result = Result { try FileManager.default.copyItem(at: from, to: to) }
        }
        try finish(result, error)
    }

    static func remove(_ url: URL) throws {
        try StagedFolder.guardWrite(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        try finish(result, error)
    }

    static func trash(_ url: URL) throws {
        if StagedFolder.fence != nil { return try remove(url) }
        try trash(
            url, trashItem: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
            trashFolder: { try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: $0, create: true) })
    }

    static func trash(_ url: URL, trashItem: (URL) throws -> Void, trashFolder: (URL) throws -> URL) throws {
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            result = Result {
                do { try trashItem(url) } catch let denied as CocoaError where denied.code == .fileWriteNoPermission {
                    // iCloud Drive의 어떤 파일은 `trashItem`이 권한 오류(513)로 실패하는데, 같은 파일을 휴지통 폴더로 옮기는 이름
                    // 바꾸기는 성공한다(macOS 26에서 확인했고 어떤 파일이 그런지는 재현하지 못했다). 지울 파일은 휴지통에 남긴다고
                    // 약속했으므로 지우지 않고 옮긴다. 옮기지도 못하면 처음 오류를 알린다.
                    guard let folder = try? trashFolder(url) else { throw denied }
                    do { try FileManager.default.moveItem(at: url, to: freeName(for: url.lastPathComponent, in: folder)) } catch {
                        throw denied
                    }
                }
            }
        }
        try finish(result, error)
    }

    // 휴지통에 같은 이름이 있으면 Finder처럼 ` 2`, ` 3`을 붙인다.
    static func freeName(for name: String, in folder: URL) -> URL {
        let parts = FileNameParts(name)
        var candidate = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(parts.stem) \(n)\(parts.suffix)")
            n += 1
        }
        return candidate
    }

    private static func appendUncoordinated(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    static func unresolvedConflicts(_ url: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    @discardableResult
    private static func finish<T>(_ result: Result<T, any Error>?, _ error: NSError?) throws -> T {
        if let error { throw error }
        guard let result else { throw StorageError.coordination("accessor was not called") }
        return try result.get()
    }
}

extension StoredDocument {
    public static func hasConflicts(at url: URL) -> Bool {
        !CoordinatedFile.unresolvedConflicts(url).isEmpty
    }
}
