import CryptoKit
import FolioDomain
import Foundation
import Synchronization

enum FileHash {
    // 큰 교재를 메모리에 올리지 않도록 스트림으로 읽는다. iCloud가 아직 내려받지 않았으면 읽기가 내려받기를
    // 일으키므로 nil을 돌려준다.
    static func sha256(of url: URL) throws -> String? {
        let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        if let status, status != .current { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private struct Stamp: Equatable {
        var size: Int
        var modified: Date
    }

    private static let remembered = Mutex<[String: (stamp: Stamp, hash: String)]>([:])

    // 자료 페이지는 열 때마다 main actor 밖의 dry run으로 해시를 먼저 계산하고, 바뀐 것이 있으면 main actor에서 같은 추적을
    // 다시 돈다. 그때 큰 파일을 다시 읽어 화면을 막지 않도록 크기와 수정 시각이 같은 파일의 해시를 기억한다.
    static func trackedSHA256(of url: URL) throws -> String? {
        let key = url.standardizedFileURL.path(percentEncoded: false)
        // URL은 한 번 읽은 resource value를 기억하므로, 비우지 않으면 다시 쓴 파일의 옛 수정 시각을 읽는다.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modified = values.contentModificationDate else { return try sha256(of: url) }
        let stamp = Stamp(size: size, modified: modified)
        if let known = remembered.withLock({ $0[key] }), known.stamp == stamp { return known.hash }
        guard let hash = try sha256(of: url) else { return nil }
        remembered.withLock { $0[key] = (stamp, hash) }
        return hash
    }
}
