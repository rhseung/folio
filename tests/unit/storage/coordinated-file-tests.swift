import Foundation
import Testing

@testable import FolioStorage

// iCloud Drive에서 `trashItem`이 권한 오류로 실패하는 파일도 지워지지 않고 휴지통으로 가야 한다.
struct CoordinatedFileTrashTests {
    let folder: URL
    let trash: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "folio-trash-\(UUID().uuidString)")
        folder = root.appending(path: "Slow Problem #2")
        trash = root.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ text: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    static func denied(_ url: URL) throws { throw CocoaError(.fileWriteNoPermission, userInfo: [NSURLErrorKey: url]) }

    @Test func movesToTheTrashFolderWhenTrashingIsDenied() throws {
        let url = try file("SP2.pdf", "built")
        try CoordinatedFile.trash(url, trashItem: Self.denied, trashFolder: { _ in trash })
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try text(trash.appending(path: "SP2.pdf")) == "built")
    }

    @Test func numbersTheNameWhenTheTrashHasOneAlready() throws {
        try Data("older".utf8).write(to: trash.appending(path: "SP2.pdf"))
        try Data("old".utf8).write(to: trash.appending(path: "SP2 2.pdf"))
        let url = try file("SP2.pdf", "built")
        try CoordinatedFile.trash(url, trashItem: Self.denied, trashFolder: { _ in trash })
        #expect(try text(trash.appending(path: "SP2.pdf")) == "older")
        #expect(try text(trash.appending(path: "SP2 3.pdf")) == "built")
    }

    @Test func keepsTheFileAndReportsDenialWhenTheTrashFolderIsUnknown() throws {
        let url = try file("SP2.pdf", "built")
        #expect(throws: CocoaError(.fileWriteNoPermission)) {
            try CoordinatedFile.trash(
                url, trashItem: { _ in throw CocoaError(.fileWriteNoPermission) }, trashFolder: { _ in throw CocoaError(.fileNoSuchFile) })
        }
        #expect(try text(url) == "built")
    }

    @Test func leavesOtherErrorsAlone() throws {
        let url = try file("SP2.pdf", "built")
        #expect(throws: CocoaError(.fileWriteVolumeReadOnly)) {
            try CoordinatedFile.trash(url, trashItem: { _ in throw CocoaError(.fileWriteVolumeReadOnly) }, trashFolder: { _ in trash })
        }
        #expect(try text(url) == "built")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }
}
