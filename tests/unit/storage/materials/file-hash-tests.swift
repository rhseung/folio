import Foundation
import Testing

@testable import FolioStorage

struct FileHashTests {
    @Test func aRewrittenFileOfTheSameSizeIsHashedAgain() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-hash-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("first".utf8).write(to: url)
        let first = try FileHash.trackedSHA256(of: url)
        #expect(first == (try FileHash.sha256(of: url)))
        #expect(try FileHash.trackedSHA256(of: url) == first)

        try Data("other".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: url.path)
        let second = try FileHash.trackedSHA256(of: url)
        #expect(second != first)
        #expect(second == (try FileHash.sha256(of: url)))
    }
}
