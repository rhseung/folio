import Darwin
import Foundation

/// A throwaway copy of a GIST folder that actions run in for real, so a change that builds on earlier unapplied ones
/// (a unit's pages after the unit, an edit after a new note) is checked, and read back, as it will be once those are
/// applied. The original is never written: inside `run`, `CoordinatedFile` refuses any write that would land outside
/// the copy.
///
/// Files are APFS clones, which take no room and part from the original on the first write. A file iCloud has evicted
/// (dataless) is not cloned, since cloning would download it: the copy holds a link to the original instead, and a
/// write through the copy first replaces the link with the file's bytes. A `.git` folder is linked whole, since
/// nothing writes into one and a code assignment's history can hold thousands of files.
public final class StagedFolder: @unchecked Sendable {
    /// The copy of the GIST folder, under the same name.
    public let url: URL
    private let base: URL

    @TaskLocal static var fence: URL?

    public init(copying source: URL) throws {
        let fm = FileManager.default
        let source = source.standardizedFileURL
        // On the original's volume, where cloning works; never inside the GIST folder, which iCloud would sync.
        let near = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: source, create: true)
        if let near, !Self.isInside(near.standardizedFileURL.path, source.path) {
            base = near
        } else {
            if let near { try? fm.removeItem(at: near) }
            base = fm.temporaryDirectory.appending(path: "folio-stage-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        url = base.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Self.mirror(source.path, into: url.path)
        } catch {
            remove()
            throw error
        }
    }

    deinit { remove() }

    public func run<T>(_ body: () throws -> T) rethrows -> T {
        try Self.$fence.withValue(url) { try body() }
    }

    public func remove() { try? FileManager.default.removeItem(at: base) }

    static let dataless: UInt32 = 0x4000_0000  // SF_DATALESS in <sys/stat.h>

    private static func mirror(_ source: String, into target: String) throws {
        let fm = FileManager.default
        guard let walk = fm.enumerator(atPath: source) else { throw StorageError.coordination("unreadable: \(source)") }
        while let relative = walk.nextObject() as? String {
            let from = source + "/" + relative, to = target + "/" + relative
            var info = stat()
            guard lstat(from, &info) == 0 else { continue }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                if (relative as NSString).lastPathComponent == ".git" {
                    try fm.createSymbolicLink(atPath: to, withDestinationPath: from)
                    walk.skipDescendants()
                } else {
                    try fm.createDirectory(atPath: to, withIntermediateDirectories: true)
                }
            case S_IFLNK:
                try fm.createSymbolicLink(atPath: to, withDestinationPath: try fm.destinationOfSymbolicLink(atPath: from))
            case S_IFREG:
                if info.st_flags & dataless != 0 || (try? fm.copyItem(atPath: from, toPath: to)) == nil {
                    try? fm.removeItem(atPath: to)
                    try fm.createSymbolicLink(atPath: to, withDestinationPath: from)
                }
            default:
                continue
            }
        }
    }

    static func isInside(_ path: String, _ root: String) -> Bool {
        let root = root.hasSuffix("/") ? String(root.dropLast()) : root
        return path == root || path.hasPrefix(root + "/")
    }

    /// The path with every link resolved, `/private` included, so two spellings of one place compare equal.
    static func real(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    /// Inside `run`: refuses a write to `url` that would reach outside the copy, by its path or through a linked folder.
    /// `detach` replaces a link at `url` with what it points to (`keep`) or with nothing, so the write lands in the copy.
    static func guardWrite(_ url: URL, detach: Bool = false, keep: Bool = false) throws {
        guard let root = fence else { return }
        let fm = FileManager.default
        let path = url.standardizedFileURL.path
        guard isInside(path, root.standardizedFileURL.path) else { throw StorageError.outsideStage(path) }
        if detach, let link = try? fm.destinationOfSymbolicLink(atPath: path) {
            let original = URL(filePath: link, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            try fm.removeItem(atPath: path)
            if keep, fm.fileExists(atPath: original.path) { try fm.copyItem(at: original, to: URL(filePath: path)) }
        }
        // The nearest folder that exists: one about to be made would otherwise be made through the link.
        var parent = url.deletingLastPathComponent().standardizedFileURL
        while real(parent.path) == nil, parent.path != "/" { parent = parent.deletingLastPathComponent() }
        if let realParent = real(parent.path), let realRoot = real(root.path), !isInside(realParent, realRoot) {
            throw StorageError.outsideStage(path)
        }
    }
}
