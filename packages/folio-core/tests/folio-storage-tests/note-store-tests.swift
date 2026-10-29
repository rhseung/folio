import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct NoteStoreTests {
    func store() throws -> CourseStore {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        return try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
    }

    @Test func listsNotesByFrontmatterID() throws {
        let notes = try store().notes()
        #expect(notes.map(\.title) == ["2주차-1"])
        #expect(notes.first?.meta.id == UUID(uuidString: "6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41"))
        #expect(notes.first?.meta.kind == .rough)
    }

    @Test func contextImagesReadEmbedsInsideTheCourseAsShrunkJPEG() throws {
        let store = try store()
        // A 2000x1000 PNG: wide enough to be shrunk to the 1568px edge.
        let ctx = try #require(CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let png = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        let path = try store.addNoteAsset(named: "board.png", data: png as Data)
        let outside = store.url.deletingLastPathComponent().appending(path: "secret.png")
        try (png as Data).write(to: outside)
        let note = try store.createNote(title: "그림", meta: NoteMeta(), body: "")

        let images = store.contextImages(of: note, body: "![b|400](\(path)) ![[board.png]] ![x](../../secret.png) ![y](assets/none.png)")
        #expect(images.map(\.name) == ["board.png", "board.png"])
        let source = try #require(CGImageSourceCreateWithData(images[0].data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1568)
    }

    @Test func createsFromTemplateWithUniqueNames() throws {
        let store = try store()
        let unit = UUID()
        let a = try store.createNote(title: "2주차-1 정리", meta: NoteMeta(kind: .review, unitIds: [unit]))
        let b = try store.createNote(title: "2주차-1 정리", meta: NoteMeta(kind: .review))
        #expect(a.title == "2주차-1 정리" && b.title == "2주차-1 정리 2")

        let text = try store.read(a)
        #expect(text.contains("## 핵심 정의와 정리"))
        let found = try #require(try store.note(id: a.meta.id!))
        #expect(found.meta.unitIds == [unit] && found.meta.kind == .review)
    }

    @Test func savingKeepsUnknownFrontmatter() throws {
        let store = try store()
        var note = try #require(try store.notes().first)
        let original = "---\nid: \(note.meta.id!.uuidString)\nkind: rough\ncssclasses: wide\n---\n# 2주차-1\n"
        try store.save(note, text: original)
        note.meta.tags = ["matching"]
        try store.save(note, text: try store.read(note))
        let text = try store.read(note)
        #expect(text.contains("cssclasses: wide"))
        #expect(text.contains("tags: [matching]"))
    }

    @Test func assetsAndExportsAreNotNotes() throws {
        let store = try store()
        let notes = store.url.appending(path: "Notes")
        for folder in ["assets/x", "Exports"] {
            try FileManager.default.createDirectory(at: notes.appending(path: folder), withIntermediateDirectories: true)
        }
        try Data("# img".utf8).write(to: notes.appending(path: "assets/x/readme.md"))
        try Data("# pdf".utf8).write(to: notes.appending(path: "Exports/summary.md"))
        #expect(try store.notes().count == 1)
    }

    @Test func assetsAreReusedOrNumberedButNeverOverwritten() throws {
        let store = try store()
        let first = try store.addNoteAsset(named: "graph.png", data: Data("first".utf8))
        #expect(first == "assets/graph.png")
        #expect(try store.addNoteAsset(named: "graph.png", data: Data("first".utf8)) == "assets/graph.png")
        #expect(try store.addNoteAsset(named: "graph.png", data: Data("second".utf8)) == "assets/graph 2.png")
        #expect(try Data(contentsOf: store.noteAssetsURL.appending(path: "graph.png")) == Data("first".utf8))
        #expect(Set(store.noteAssets().map(\.lastPathComponent)) == ["graph.png", "graph 2.png"])
    }

    @Test func mathSyntaxRoundTripsThroughFrontmatterAndDefaultsToLatex() throws {
        let store = try store()
        let ascii = try store.createNote(title: "ascii", meta: NoteMeta(math: .asciimath), body: "x")
        let tex = try store.createNote(title: "tex", meta: NoteMeta(), body: "x")
        #expect(try store.read(ascii).contains("math: asciimath"))
        #expect(!(try store.read(tex).contains("math:")))
        #expect(try store.note(id: ascii.meta.id!)?.meta.math == .asciimath)
        #expect(try store.note(id: tex.meta.id!)?.meta.math == .latex)
    }
}

struct NotionNotesWriterTests {
    @Test func writesConvertedNoteAndImageWithoutOverwriting() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        let dumpFolder = FileManager.default.temporaryDirectory.appending(path: "notion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dumpFolder.appending(path: "assets"), withIntermediateDirectories: true)
        try Data("<callout icon=\"⚠️\">\n<b>주의</b>\n본문\n</callout>\n<image source=\"notion-file-block://x?name=a.svg\" />".utf8)
            .write(to: dumpFolder.appending(path: "n.md"))
        try Data("<svg/>".utf8).write(to: dumpFolder.appending(path: "assets/a.svg"))
        let id = UUID()
        let dump = NotionCourseDump(coursePageId: UUID(), title: "", notes: [], scores: [],
                                    images: [.init(source: "notion-file-block://x?name=a.svg", file: "assets/a.svg")])
        let plan = NotionNotePlan(id: id, title: "7주차-2 정리", meta: NoteMeta(id: id, kind: .review), sourceFile: "n.md")

        try store.writeNotionNotes([plan], dump: dump, folder: dumpFolder, links: [:])
        let note = try #require(try store.note(id: id))
        let text = try store.read(note)
        #expect(text.contains("> [!warning] 주의\n> 본문"))
        #expect(text.contains("![](assets/a.svg)"))
        #expect(FileManager.default.fileExists(atPath: store.url.appending(path: "Notes/assets/a.svg").path))

        try store.writeNotionNotes([plan], dump: dump, folder: dumpFolder, links: [:])
        #expect(try store.notes().filter { $0.meta.id == id }.count == 1)
    }
}

struct RecordingStoreTests {
    @Test func recordingFilesNeverCollideAndTranscriptsRoundTrip() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let first = try store.newRecordingFile(named: "3주차-1")
        #expect(first == "Recordings/3주차-1.m4a")
        try Data("audio".utf8).write(to: store.fileURL(first))
        #expect(try store.newRecordingFile(named: "3주차-1") == "Recordings/3주차-1 2.m4a")

        let recording = Recording(device: UUID(), at: .now, sessionId: nil, file: first)
        let transcript = LectureTranscript(locale: "ko_KR", lines: [.init(start: 0, end: 2.5, text: "그래프의 정의")])
        try store.saveTranscript(transcript, of: recording)
        #expect(store.transcript(of: recording) == transcript)
    }

    @Test func pendingAudioMovesInWithoutReplacingAFileThatTookItsName() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let pending = PendingRecordings(url: gist.url.deletingLastPathComponent().appending(path: "pending"))
        let recording = Recording(device: UUID(), at: Date(timeIntervalSince1970: 3_000_000), sessionId: nil, file: try store.newRecordingFile(named: "3주차-1"))
        try pending.save(PendingRecording(courseId: UUID(), recording: recording))
        #expect(pending.all().isEmpty)  // no audio yet
        try Data("caf".utf8).write(to: pending.audioURL(of: recording.id))
        #expect(pending.all().map(\.recording) == [recording])

        try Data("other device".utf8).write(to: store.fileURL(recording.file))
        try Data("m4a".utf8).write(to: pending.compressedURL(of: recording.id))
        let landed = try store.installRecording(from: pending.compressedURL(of: recording.id), as: recording.file)
        #expect(landed == "Recordings/3주차-1 2.m4a")
        #expect(try Data(contentsOf: store.fileURL(recording.file)) == Data("other device".utf8))
        pending.remove(recording.id)
        #expect(pending.all().isEmpty)
    }

    @Test func deletingARecordingRemovesAudioAndTranscriptOnly() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let file = try store.newRecordingFile(named: "3주차-1")
        try Data("audio".utf8).write(to: store.fileURL(file))
        let other = try store.newRecordingFile(named: "3주차-1")
        try Data("audio".utf8).write(to: store.fileURL(other))
        let recording = Recording(device: UUID(), at: .now, sessionId: nil, file: file)
        try store.saveTranscript(LectureTranscript(locale: "ko_KR", lines: []), of: recording)

        try store.deleteFiles(of: recording)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(file).path))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(recording.transcriptFile).path))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(other).path))
        try store.deleteFiles(of: recording)  // already gone: not an error
    }
}
