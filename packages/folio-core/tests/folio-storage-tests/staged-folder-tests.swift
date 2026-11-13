@testable import FolioStorage
import Foundation
import Testing

/// #90: the panel's proposals run for real in a staged copy, which must never write the original.
struct StagedFolderTests {
    let source: URL

    init() throws {
        source = FileManager.default.temporaryDirectory.appending(path: "folio-stage-source-\(UUID().uuidString)/GIST")
        let fm = FileManager.default
        try fm.createDirectory(at: source.appending(path: ".folio/logs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appending(path: "2026-3/EC4207/Assignments/Code/.git/objects"), withIntermediateDirectories: true)
        try Data("note".utf8).write(to: source.appending(path: "2026-3/EC4207/note.md"))
        try Data("line 1\n".utf8).write(to: source.appending(path: ".folio/logs/device.jsonl"))
        try Data("ref".utf8).write(to: source.appending(path: "2026-3/EC4207/Assignments/Code/.git/HEAD"))
    }

    func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    func isLink(_ url: URL) -> Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }

    @Test func copiesTheTreeAndRemovesItself() throws {
        let copy = try StagedFolder(copying: source)
        #expect(copy.url.lastPathComponent == "GIST")
        #expect(!StagedFolder.isInside(copy.url.standardizedFileURL.path, source.standardizedFileURL.path))
        #expect(try text(copy.url.appending(path: "2026-3/EC4207/note.md")) == "note")
        #expect(!isLink(copy.url.appending(path: "2026-3/EC4207/note.md")))

        // Linked whole, never copied file by file.
        #expect(isLink(copy.url.appending(path: "2026-3/EC4207/Assignments/Code/.git")))
        let made = copy.url
        copy.remove()
        #expect(!FileManager.default.fileExists(atPath: made.path))
    }

    @Test func writesLandInTheCopyOnly() throws {
        let copy = try StagedFolder(copying: source)
        defer { copy.remove() }
        try copy.run {
            try CoordinatedFile.write(Data("changed".utf8), to: copy.url.appending(path: "2026-3/EC4207/note.md"))
            try CoordinatedFile.append(Data("line 2\n".utf8), to: copy.url.appending(path: ".folio/logs/device.jsonl"))
            try CoordinatedFile.create(Data("new".utf8), at: copy.url.appending(path: "2026-3/EC4207/Notes/new.md"))
            try CoordinatedFile.trash(copy.url.appending(path: "2026-3/EC4207/Notes/new.md"))
        }
        #expect(try text(copy.url.appending(path: "2026-3/EC4207/note.md")) == "changed")
        #expect(try text(source.appending(path: "2026-3/EC4207/note.md")) == "note")
        #expect(try text(source.appending(path: ".folio/logs/device.jsonl")) == "line 1\n")
        #expect(try text(copy.url.appending(path: ".folio/logs/device.jsonl")) == "line 1\nline 2\n")

        // Removed in the copy, not put in the user's Trash.
        #expect(!FileManager.default.fileExists(atPath: copy.url.appending(path: "2026-3/EC4207/Notes/new.md").path))
        #expect(!FileManager.default.fileExists(atPath: source.appending(path: "2026-3/EC4207/Notes").path))
    }

    /// An evicted iCloud file is a link in the copy; writing it must not write through to the original.
    @Test func aLinkedFileIsDetachedBeforeAWrite() throws {
        let copy = try StagedFolder(copying: source)
        defer { copy.remove() }
        let fm = FileManager.default
        for path in ["2026-3/EC4207/note.md", ".folio/logs/device.jsonl"] {
            try fm.removeItem(at: copy.url.appending(path: path))
            try fm.createSymbolicLink(at: copy.url.appending(path: path), withDestinationURL: source.appending(path: path))
        }
        try copy.run {
            try CoordinatedFile.write(Data("changed".utf8), to: copy.url.appending(path: "2026-3/EC4207/note.md"))
            try CoordinatedFile.append(Data("line 2\n".utf8), to: copy.url.appending(path: ".folio/logs/device.jsonl"))
        }
        #expect(try text(source.appending(path: "2026-3/EC4207/note.md")) == "note")
        #expect(try text(source.appending(path: ".folio/logs/device.jsonl")) == "line 1\n")
        #expect(!isLink(copy.url.appending(path: "2026-3/EC4207/note.md")))
        #expect(try text(copy.url.appending(path: ".folio/logs/device.jsonl")) == "line 1\nline 2\n")
    }

    @Test func aWriteOutsideTheCopyIsRefused() throws {
        let copy = try StagedFolder(copying: source)
        defer { copy.remove() }
        #expect(throws: StorageError.self) {
            try copy.run { try CoordinatedFile.write(Data("x".utf8), to: source.appending(path: "2026-3/EC4207/note.md")) }
        }
        #expect(throws: StorageError.self) {
            try copy.run { try CoordinatedFile.write(Data("x".utf8), to: copy.url.appending(path: "2026-3/EC4207/Assignments/Code/.git/HEAD")) }
        }
        #expect(throws: StorageError.self) {
            try copy.run { try CoordinatedFile.write(Data("x".utf8), to: copy.url.appending(path: "2026-3/EC4207/Assignments/Code/.git/new/file")) }
        }
        #expect(try text(source.appending(path: "2026-3/EC4207/note.md")) == "note")
        #expect(try text(source.appending(path: "2026-3/EC4207/Assignments/Code/.git/HEAD")) == "ref")
        #expect(!FileManager.default.fileExists(atPath: source.appending(path: "2026-3/EC4207/Assignments/Code/.git/new").path))

        // Outside `run` the fence is off, as for every other write.
        try CoordinatedFile.write(Data("x".utf8), to: source.appending(path: "other.txt"))
    }
}
