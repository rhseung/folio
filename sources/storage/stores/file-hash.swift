import CryptoKit
import FolioDomain
import Foundation

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
}
