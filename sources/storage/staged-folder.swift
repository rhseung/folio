import Darwin
import Foundation

// 적용하지 않은 앞 변경에 기대는 변경(단원 뒤의 단원 쪽, 새 노트 뒤의 편집)을 적용된 뒤와 같게 검사하고 다시 읽으려고,
// 액션을 사본에서 실제로 돌린다. `run` 안에서는 `CoordinatedFile`이 사본 밖으로 가는 쓰기를 거절하므로 원본에는
// 쓰지 않는다.
//
// 파일은 APFS 복제라 자리를 차지하지 않고, 처음 쓸 때 원본과 나뉜다. iCloud가 비운(dataless) 파일은 복제하면
// 내려받게 되므로, 사본에 원본으로 가는 링크를 두고 처음 쓸 때 링크를 파일 내용으로 바꾼다. `.git` 폴더는 아무도
// 쓰지 않고 코드 과제의 기록이 파일 수천 개일 수 있으므로 통째로 링크한다.
public final class StagedFolder: @unchecked Sendable {
    public let url: URL
    private let base: URL

    @TaskLocal static var fence: URL?

    public init(copying source: URL) throws {
        let fm = FileManager.default
        let source = source.standardizedFileURL
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

    // `<sys/stat.h>`의 `SF_DATALESS`이다.
    static let dataless: UInt32 = 0x4000_0000

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

    static func real(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

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
        // 있는 폴더 중 가장 가까운 것을 본다. 그러지 않으면 곧 만들 폴더가 링크를 거쳐 만들어진다.
        var parent = url.deletingLastPathComponent().standardizedFileURL
        while real(parent.path) == nil, parent.path != "/" { parent = parent.deletingLastPathComponent() }
        if let realParent = real(parent.path), let realRoot = real(root.path), !isInside(realParent, realRoot) {
            throw StorageError.outsideStage(path)
        }
    }
}
