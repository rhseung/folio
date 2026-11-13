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

    @Test func notesTakeTheirPropertiesFromCourseJSON() throws {
        let notes = try store().notes()
        #expect(notes.map(\.title) == ["09-08(화) 매칭"])
        #expect(notes.first?.meta.id == UUID(uuidString: "6F1D2C4E-8A3B-4F5E-9C1D-2B7A8E0F3D41"))
        #expect(notes.first?.meta.kind == .rough)
        #expect(try store().read(#require(notes.first)).hasPrefix("# 09-08(화) 매칭"))
    }

    /// A link's title finds its note as written first, and otherwise ignoring case.
    @Test func aLinkFindsItsNoteByTitle() throws {
        let store = try store()
        try store.createNote(at: store.newNoteURL(title: "Matching", format: .markdown), text: "")
        let notes = try store.notes()
        #expect(notes.titled("Matching")?.url.lastPathComponent == "Matching.md")
        #expect(notes.titled("MATCHING")?.url.lastPathComponent == "Matching.md")
        #expect(notes.titled("09-08(화) 매칭")?.meta.id != nil)
        #expect(notes.titled("없음") == nil)

        // A link may name the file; a `.tex` note is still a note to open.
        try store.createNote(at: store.newNoteURL(title: "증명", format: .tex), text: "")
        let all = try store.notes()
        #expect(all.linked("Matching.md")?.url.lastPathComponent == "Matching.md")
        #expect(all.linked("matching")?.url.lastPathComponent == "Matching.md")
        #expect(all.linked("증명")?.format == .tex)
        #expect(all.linked("없음.md") == nil)
    }

    @Test func aFileWithoutAnEntryHasNoIDAndATexFileIsANote() throws {
        let store = try store()
        try store.createNote(at: store.newNoteURL(title: "밖에서", format: .markdown), text: "# 밖에서\n")
        try store.createNote(at: store.newNoteURL(title: "증명", format: .tex), text: "\\documentclass{article}\n")
        let notes = try store.notes()
        #expect(notes.map(\.title) == ["09-08(화) 매칭", "밖에서", "증명"])
        #expect(notes[1].meta.id == nil && notes[1].format == .markdown)
        #expect(notes[2].meta.id == nil && notes[2].format == .tex)
        #expect(try store.note(at: "Notes/증명.tex")?.format == .tex)
    }

    @Test func newNamesNeverTakeAnExistingFile() throws {
        let store = try store()
        let first = store.newNoteURL(title: "09-08(화) 매칭 정리", format: .markdown)
        try store.createNote(at: first, text: "")
        #expect(first.lastPathComponent == "09-08(화) 매칭 정리.md")
        #expect(store.newNoteURL(title: "09-08(화) 매칭 정리", format: .markdown).lastPathComponent == "09-08(화) 매칭 정리 2.md")

        // The title is the file name, so another format doesn't free it.
        #expect(store.newNoteURL(title: "09-08(화) 매칭 정리", format: .tex).lastPathComponent == "09-08(화) 매칭 정리 2.tex")
        #expect(store.newNoteURL(title: "숙제", format: .markdown, avoiding: ["숙제", "숙제 2"]).lastPathComponent == "숙제 3.md")
        #expect(store.newNoteURL(title: "a/b:c", format: .markdown).lastPathComponent == "a-b-c.md")
    }

    /// A moved note avoids every other note's title in the course, whatever its folder, case or Unicode form (macOS
    /// hands back decomposed Hangul), and keeps its own.
    @Test func aMovedNoteAvoidsOtherNotesTitles() throws {
        let store = try store()
        let folder = store.url.appending(path: "Notes/정리")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try store.createNote(at: folder.appending(path: "증명".decomposedStringWithCanonicalMapping + ".tex"), text: "")
        let file = try store.load().model
        let note = try #require(try store.note(at: "Notes/09-08(화) 매칭.md"))
        let moved = { (to: String) in store.movedNoteURL(note, to: to, in: file).flatMap { store.coursePath(of: $0) } }
        #expect(moved("증명") == "Notes/증명 2.md")
        #expect(moved("정리/09-08(화) 매칭.md") == "Notes/정리/09-08(화) 매칭.md")
        #expect(moved("09-08(화) 매칭") == "Notes/09-08(화) 매칭.md")
        #expect(moved("정리/assets/x") == nil && moved("x.tex") == nil && moved("Exports/x") == nil && moved("Assets/x") == nil)
        #expect(store.noteFolders() == ["", "정리"])
    }

    @Test func writingLeavesTheTextAsGiven() throws {
        let store = try store()
        let note = try #require(try store.notes().first)
        let text = "---\ncssclasses: wide\n---\n# 09-08(화) 매칭\n"
        try store.write(note, text: text)
        #expect(try store.read(note) == text)
        #expect(try store.notes().first?.meta.id == note.meta.id)
    }

    @Test func frontmatterNotesLoseOnlyFolioKeys() throws {
        let store = try store()
        let id = UUID(), session = UUID()
        let old = store.newNoteURL(title: "예전", format: .markdown)
        try store.createNote(at: old, text: "---\nid: \(id.uuidString)\nkind: review\nsessionId: \(session.uuidString)\ncssclasses: wide\nmath: asciimath\n---\n# 예전\n")
        let bare = store.newNoteURL(title: "그냥", format: .markdown)
        try store.createNote(at: bare, text: "---\nid: \(UUID().uuidString)\n---\n# 그냥\n")
        try store.createNote(at: store.newNoteURL(title: "남의 것", format: .markdown), text: "---\naliases: [x]\n---\n# 남의 것\n")

        let found = try store.frontmatterNotes()
        #expect(found.map(\.url.lastPathComponent) == ["그냥.md", "예전.md"])
        let note = try #require(found.last)
        #expect(note.meta.id == id && note.meta.kind == .review && note.meta.sessionId == session && note.meta.math == .asciimath)
        #expect(note.text == "---\ncssclasses: wide\n---\n# 예전\n")
        #expect(found.first?.text == "# 그냥\n")
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
        let url = store.newNoteURL(title: "그림", format: .markdown)
        try store.createNote(at: url, text: "")
        let note = NoteFile(url: url, meta: NoteMeta())

        let images = store.contextImages(of: note, body: "![b|400](\(path)) ![[board.png]] ![x](../../secret.png) ![y](assets/none.png)")
        #expect(images.map(\.name) == ["board.png", "board.png"])
        let source = try #require(CGImageSourceCreateWithData(images[0].data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1568)
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

        let url = store.newNoteURL(title: plan.title, format: .markdown)
        try store.writeNotionNotes([plan], dump: dump, folder: dumpFolder, links: [:], at: [id: url])
        #expect(url.lastPathComponent == "7주차-2 정리.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("> [!warning] 주의\n> 본문"))
        #expect(text.contains("![](assets/a.svg)"))
        #expect(FileManager.default.fileExists(atPath: store.url.appending(path: "Notes/assets/a.svg").path))

        try store.writeNotionNotes([plan], dump: dump, folder: dumpFolder, links: [:], at: [:])
        #expect(!FileManager.default.fileExists(atPath: store.url.appending(path: "Notes/7주차-2 정리 2.md").path))
    }
}

struct RecordingStoreTests {
    @Test func recordingFilesNeverCollideAndTranscriptsRoundTrip() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let first = try store.newRecordingFile(named: "11-03(화)")
        #expect(first == "Recordings/11-03(화).m4a")
        try Data("audio".utf8).write(to: store.fileURL(first))
        #expect(try store.newRecordingFile(named: "11-03(화)") == "Recordings/11-03(화) 2.m4a")

        let recording = Recording(device: UUID(), at: .now, sessionId: nil, file: first)
        let transcript = LectureTranscript(locale: "ko_KR", lines: [.init(start: 0, end: 2.5, text: "그래프의 정의")])
        try store.saveTranscript(transcript, of: recording)
        #expect(store.transcript(of: recording) == transcript)
    }

    @Test func pendingAudioMovesInWithoutReplacingAFileThatTookItsName() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let pending = PendingRecordings(url: gist.url.deletingLastPathComponent().appending(path: "pending"))
        let recording = Recording(device: UUID(), at: Date(timeIntervalSince1970: 3_000_000), sessionId: nil, file: try store.newRecordingFile(named: "11-03(화)"))
        try pending.save(PendingRecording(courseId: UUID(), recording: recording))
        #expect(pending.all().isEmpty)  // no audio yet
        try Data("caf".utf8).write(to: pending.audioURL(of: recording.id))
        #expect(pending.all().map(\.recording) == [recording])

        try Data("other device".utf8).write(to: store.fileURL(recording.file))
        try Data("m4a".utf8).write(to: pending.compressedURL(of: recording.id))
        let landed = try store.installRecording(from: pending.compressedURL(of: recording.id), as: recording.file)
        #expect(landed == "Recordings/11-03(화) 2.m4a")
        #expect(try Data(contentsOf: store.fileURL(recording.file)) == Data("other device".utf8))
        pending.remove(recording.id)
        #expect(pending.all().isEmpty)
    }

    @Test func deletingARecordingRemovesAudioAndTranscriptOnly() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        let file = try store.newRecordingFile(named: "11-03(화)")
        try Data("audio".utf8).write(to: store.fileURL(file))
        let other = try store.newRecordingFile(named: "11-03(화)")
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
