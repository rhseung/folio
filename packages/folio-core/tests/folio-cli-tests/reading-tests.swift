@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// The panel's reading tools (#85): a PDF's pages, a recording's transcript, a note's pictures.
struct ReadingTests {
    let h = Harness()
    static let recording = UUID(uuidString: "A0000000-0000-4000-8000-0000000000D1")!

    func course(_ gist: URL) throws -> CourseStore {
        try ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now).store(Harness.graphTheory)
    }

    /// A real deck (the fixture's own PDFs are placeholders PDFKit can't open), tracked as a material.
    func withDeck() throws -> URL {
        let gist = try Harness.fixtureCopy()
        try SampleLecture.write(to: try course(gist).fileURL("Lectures/06_Hall.pdf"))
        #expect(h.cli(["material", "track", "EC4207"], gist: gist).code == 0)
        return gist
    }

    func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func array(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let a)? = v { a } else { [] }
    }

    func int(_ v: JSONValue?) -> Int? {
        if case .number(let n)? = v { Int(n) } else { nil }
    }

    func string(_ v: JSONValue?) -> String? {
        if case .string(let s)? = v { s } else { nil }
    }

    // MARK: PDF pages

    @Test func aPageRangeReadsItsPagesTitlesAndText() throws {
        let gist = try withDeck()
        let r = h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "3-5", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let shown = try json(r.out)
        #expect(int(shown["first"]) == 3 && int(shown["last"]) == 5 && int(shown["pageCount"]) == 24)
        let pages = array(shown["pages"])
        #expect(pages.map { string($0["title"]) } == ["Examples", "Maximum matchings", "Alternating paths"])
        #expect(string(pages.first?["text"])?.contains("Slide 3, point 1") == true)
        #expect(shown["next"] == nil || shown["next"] == .null)
    }

    @Test func titlesSkimTheWholeDeckWithoutText() throws {
        let gist = try withDeck()
        let shown = try json(h.cli(["material", "read", "EC4207/06_Hall.pdf", "--titles", "--json"], gist: gist).out)
        let pages = array(shown["pages"])
        #expect(pages.count == 24)
        #expect(pages.allSatisfy { $0["text"] == nil || $0["text"] == .null })
        #expect(int(pages[0]["words"]) == 0 && int(pages[1]["words"]).map { $0 > 20 } == true)
    }

    @Test func picturesCapTheReadAndSayWhereToGoOn() throws {
        let gist = try withDeck()
        let r = h.cli(["material", "read", "EC4207/06_Hall.pdf", "--images", "--json"], gist: gist)
        #expect(r.code == 0)
        let shown = try json(r.out)
        #expect(int(shown["last"]) == ReadingLimit.images)
        #expect(string(shown["next"]) == "\(ReadingLimit.images + 1)-\(2 * ReadingLimit.images)")
        // At a terminal without --out the pictures go nowhere, and it says how to get them.
        #expect(r.err.contains("--out"))
    }

    @Test func picturesGoToFilesOutsideTheGISTOnly() throws {
        let gist = try withDeck()
        let out = FileManager.default.temporaryDirectory.appending(path: "pages-\(UUID().uuidString)")
        let r = h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "2", "--images", "--out", out.path, "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let file = try #require(string(array(try json(r.out)["pages"]).first?["image"]))
        #expect(FileManager.default.fileExists(atPath: file) && file.hasSuffix("06_Hall.pdf p2.jpg"))
        let inside = h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "2", "--images", "--out", gist.appending(path: "pages").path], gist: gist)
        #expect(inside.code == Exit.usage.rawValue)
        #expect(!FileManager.default.fileExists(atPath: gist.appending(path: "pages").path))
    }

    @Test func pagesOutsideTheFileOrMiswrittenAreRefused() throws {
        let gist = try withDeck()
        #expect(h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "30-40"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "x"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "5-3"], gist: gist).code == Exit.usage.rawValue)
        let open = try json(h.cli(["material", "read", "EC4207/06_Hall.pdf", "--pages", "20-", "--json"], gist: gist).out)
        #expect(int(open["first"]) == 20 && int(open["last"]) == 24)
    }

    // MARK: Transcript

    func record(_ gist: URL, lines: [LectureTranscript.Line]?) throws {
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        let store = try ctx.store(Harness.graphTheory)
        let rec = Recording(id: Self.recording, device: h.device, at: h.now, sessionId: nil, file: "Recordings/10-26(월).m4a", duration: 4500)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        if let lines { try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: lines), of: rec) }
        try ctx.edit(Harness.graphTheory) { $0.recordings.append(rec) }
    }

    @Test func aTranscriptIsCutToTheAskedSpan() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist, lines: [.init(start: 30, end: 40, text: "매칭의 정의"), .init(start: 75, end: 90, text: "홀의 정리"), .init(start: 200, end: 210, text: "증명")])
        let r = h.cli(["recording", "transcript", "EC4207/10-26(월).m4a", "--from", "1:00", "--to", "3:00", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let lines = array(try json(r.out)["lines"])
        #expect(lines.map { string($0["text"]) } == ["홀의 정리"])
        #expect(lines.map { string($0["at"]) } == ["1:15"])
        #expect(h.cli(["recording", "transcript", "EC4207/10-26(월).m4a", "--from", "soon"], gist: gist).code == Exit.usage.rawValue)
    }

    @Test func aLongTranscriptStopsAtTheLimitAndGoesOnFromThere() throws {
        let gist = try Harness.fixtureCopy()
        let text = String(repeating: "가", count: 299)
        try record(gist, lines: (0..<100).map { .init(start: Double($0 * 30), end: Double($0 * 30 + 29), text: text) })
        let first = try json(h.cli(["recording", "transcript", "EC4207/10-26(월).m4a", "--json"], gist: gist).out)
        let count = array(first["lines"]).count
        #expect(count == ReadingLimit.transcript / 300)
        let next = try #require(string(first["next"]))
        #expect(next == AppLink.clock(count * 30))
        let second = try json(h.cli(["recording", "transcript", "EC4207/10-26(월).m4a", "--from", next, "--json"], gist: gist).out)
        #expect(string(array(second["lines"]).first?["at"]) == next)
    }

    @Test func aRecordingWithoutATranscriptSaysSo() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist, lines: nil)
        #expect(h.cli(["recording", "transcript", "EC4207/10-26(월).m4a"], gist: gist).code == Exit.notFound.rawValue)
    }

    // MARK: Note pictures

    static func png(width: Int = 2000, height: Int = 1000) throws -> Data {
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let png = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        return png as Data
    }

    /// The fixture's note with a board photo and a picture the course doesn't have.
    func withPicture() throws -> URL {
        let gist = try Harness.fixtureCopy()
        let store = try course(gist)
        let path = try store.addNoteAsset(named: "board.png", data: try Self.png())
        let note = try #require(try store.notes().first)
        try (try store.read(note) + "\n![칠판](\(path))\n![[gone.jpg]]\n").write(to: note.url, atomically: true, encoding: .utf8)
        return gist
    }

    @Test func aNotesPicturesListInOrderWithTheMissingOnes() throws {
        let gist = try withPicture()
        let r = h.cli(["note", "images", "EC4207/09-08(화) 매칭", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let pictures = array(try json(r.out)["pictures"])
        #expect(pictures.map { string($0["written"]) } == ["assets/board.png", "gone.jpg"])
        #expect(pictures.map { string($0["path"]) } == ["Notes/assets/board.png", nil])
        let assets = array(try json(h.cli(["note", "images", "EC4207", "--json"], gist: gist).out)["pictures"])
        #expect(assets.map { string($0["path"]) } == ["Notes/assets/board.png"])
        #expect(h.cli(["note", "images", "EC4207", "--file", "../secret.png"], gist: gist).code == Exit.notFound.rawValue)
        #expect(h.cli(["note", "images", "EC4207", "--file", "notes.txt"], gist: gist).code == Exit.usage.rawValue)
    }

    // MARK: MCP

    func content(_ server: MCPServer, _ gist: URL, _ name: String, _ arguments: JSONValue) throws -> (isError: Bool, blocks: [JSONValue]) {
        let line = MCPServer.string(["jsonrpc": "2.0", "id": .number(1), "method": "tools/call", "params": ["name": .string(name), "arguments": arguments]])
        let reply = CLI.$overrides.withValue(Overrides(gist: gist, device: h.device, now: h.now, gradesUnlocked: true)) { server.handle(line) }
        let text = try #require(reply)
        let result = try #require(try json(String(decoding: text, as: UTF8.self))["result"])
        return (result["isError"] == .bool(true), array(result["content"]))
    }

    func images(_ blocks: [JSONValue]) throws -> [Data] {
        try blocks.filter { $0["type"] == .string("image") }.map { b in
            #expect(b["mimeType"] == .string("image/jpeg"))
            let data = try #require(string(b["data"]))
            return try #require(Data(base64Encoded: data))
        }
    }

    func isJPEG(_ data: Data, edge: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return false }
        return CGImageSourceGetType(source) as String? == UTType.jpeg.identifier && max(w, h) == edge
    }

    @Test func thePanelGetsPagePicturesAsImageContent() throws {
        let gist = try withDeck()
        let (failed, blocks) = try content(MCPServer(gist: nil, propose: true), gist, "material_read",
                                           ["material": "EC4207/06_Hall.pdf", "pages": "9-10", "images": .bool(true)])
        #expect(!failed)
        let pictures = try images(blocks)
        #expect(pictures.count == 2 && pictures.allSatisfy { isJPEG($0, edge: ReadingLimit.imageEdge) })
        // Each picture follows a line naming it, and the page list names it the same way.
        let labels = blocks.indices.dropLast().filter { blocks[$0 + 1]["type"] == .string("image") }.compactMap { string(blocks[$0]["text"]) }
        #expect(labels == ["06_Hall.pdf p.9", "06_Hall.pdf p.10"])
        #expect(string(blocks.first?["text"])?.contains("06_Hall.pdf p.9") == true)
    }

    @Test func thePanelGetsANotesPicturesShrunk() throws {
        let gist = try withPicture()
        let (failed, blocks) = try content(MCPServer(gist: nil, propose: true), gist, "note_images", ["note": "EC4207/09-08(화) 매칭"])
        #expect(!failed)
        let pictures = try images(blocks)
        #expect(pictures.count == 1 && isJPEG(pictures[0], edge: ReadingLimit.imageEdge))
    }

    @Test func thePanelReadsTranscriptsButCannotTouchRecordings() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist, lines: [.init(start: 0, end: 5, text: "매칭")])
        let (failed, blocks) = try content(MCPServer(gist: nil, propose: true), gist, "recording_transcript", ["recording": "EC4207/10-26(월).m4a"])
        #expect(!failed && string(blocks.first?["text"])?.contains("매칭") == true)
        guard case .array(let tools)? = try json(String(decoding: try #require(MCPServer(gist: nil, propose: true).handle(
            MCPServer.string(["jsonrpc": "2.0", "id": .number(1), "method": "tools/list"]))), as: UTF8.self))["result"]?["tools"] else {
            Issue.record("no tools"); return
        }
        let names = Set(tools.compactMap { string($0["name"]) })
        for tool in ["material_read", "recording_transcript", "note_images"] { #expect(names.contains(tool), "\(tool) is not in the panel") }
        for tool in ["recording_retitle", "recording_trim"] { #expect(!names.contains(tool)) }
    }
}
