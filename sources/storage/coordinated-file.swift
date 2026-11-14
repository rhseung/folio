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
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            result = Result { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
        try finish(result, error)
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

public enum LocalFile {
    public static func read(_ url: URL) -> Data? { try? CoordinatedFile.read(url) }
    public static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // 조정된 읽기는 iCloud 자리표시자를 내려받으므로, 파일을 직접 읽는 보기(PDFKit, Quick Look)가 그 자리에서 내용을
    // 찾는다.
    public static func download(_ url: URL) -> URL? {
        guard exists(url) else { return nil }
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { _ in }
        return error == nil ? url : nil
    }
    public static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
