import Foundation

/// All file reads and writes go through NSFileCoordinator so iCloud and other processes see consistent files.
enum CoordinatedFile {
    static func read(_ url: URL) throws -> Data {
        var error: NSError?
        var result: Result<Data, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = Result { try Data(contentsOf: url) }
        }
        return try finish(result, error)
    }

    /// Writes to a temporary file and swaps it in, so a crash never leaves a half-written file.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        try finish(result, error)
    }

    /// Appends without rewriting existing bytes; used only for append-only logs.
    static func append(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { url in
            result = Result { try appendUncoordinated(data, to: url) }
        }
        try finish(result, error)
    }

    /// Never overwrites: fails if `target` exists.
    static func move(_ source: URL, to target: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: target, options: .forReplacing, error: &error) { from, to in
            result = Result {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            }
        }
        try finish(result, error)
    }

    /// Never overwrites: fails if `target` exists.
    static func copy(_ source: URL, to target: URL) throws {
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target, options: .forReplacing, error: &error) { from, to in
            result = Result { try FileManager.default.copyItem(at: from, to: to) }
        }
        try finish(result, error)
    }

    /// A missing file is not an error.
    static func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var error: NSError?
        var result: Result<Void, any Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        try finish(result, error)
    }

    static func trash(_ url: URL) throws {
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

/// Read-only access for the app's web views, which show a note's images by absolute URL.
public enum LocalFile {
    public static func read(_ url: URL) -> Data? { try? CoordinatedFile.read(url) }
}
