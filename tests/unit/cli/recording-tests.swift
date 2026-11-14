import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

struct RecordingTrimTests {
    let h = Harness()
    static let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
    static let heard = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E1")!
    static let silent = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E2")!

    func record(_ gist: URL, course: UUID = linearAlgebra) throws {
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        let store = try ctx.store(course)
        let heard = Recording(id: Self.heard, device: h.device, at: h.now, sessionId: nil, file: "Recordings/09-01(화).m4a", duration: 60)
        let silent = Recording(id: Self.silent, device: h.device, at: h.now, sessionId: nil, file: "Recordings/09-03(목).m4a", duration: 60)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        for r in [heard, silent] { try Data("audio".utf8).write(to: store.fileURL(r.file)) }
        try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "행렬")]), of: heard)
        try ctx.edit(course) { $0.recordings = [heard, silent] }
    }

    @Test func trimMatchesTheAction() throws {
        try h.expectSame(["recording", "trim", "2026-1", "--yes"], prepare: { try record($0) }) { gist in
            RecordingTrim(
                semester: try #require(try ActionContext(gist: gist, device: h.device).file(Self.linearAlgebra).course.semesterId))
        }
    }

    @Test func trimKeepsTranscriptsAndAudioWithoutOne() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist)
        #expect(h.cli(["recording", "trim", "2026-1", "--yes"], gist: gist).code == 0)
        let store = try ActionContext(gist: GISTStore(url: gist), device: h.device).store(Self.linearAlgebra)
        let file = try h.file(GISTStore(url: gist), Self.linearAlgebra)
        let heard = try #require(file.recordings.first { $0.id == Self.heard })
        let silent = try #require(file.recordings.first { $0.id == Self.silent })
        #expect(!heard.hasAudio && heard.audioTrashedAt == h.now)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(heard.file).path))
        #expect(store.transcript(of: heard)?.lines.count == 1)
        #expect(silent.hasAudio && FileManager.default.fileExists(atPath: store.fileURL(silent.file).path))
    }

    @Test func aSemesterUnderWayIsRefused() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist, course: Harness.graphTheory)
        let r = h.cli(["recording", "trim", "2026-3", "--yes"], gist: gist)
        #expect(r.code != 0)
        #expect(try h.file(GISTStore(url: gist)).recordings.allSatisfy(\.hasAudio))
    }
}

struct RecordingRetitleTests {
    let h = Harness()
    static let old = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F1")!
    static let second = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F2")!
    static let trimmed = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F3")!
    static let mine = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F4")!

    func record(_ gist: URL) throws {
        #expect(h.cli(SessionCommandTests.add, gist: gist).code == 0)
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        let store = try ctx.store(Harness.graphTheory)
        let session = SessionCommandTests.id
        let old = Recording(id: Self.old, device: h.device, at: h.now, sessionId: session, file: "Recordings/9주차-1.m4a")
        let second = Recording(id: Self.second, device: h.device, at: h.now, sessionId: session, file: "Recordings/9주차-1 2.m4a")
        var trimmed = Recording(id: Self.trimmed, device: h.device, at: h.now, sessionId: session, file: "Recordings/9주차-2.m4a")
        trimmed.audioTrashedAt = h.now
        let mine = Recording(id: Self.mine, device: h.device, at: h.now, sessionId: session, file: "Recordings/보강.m4a")
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        for path in [old.file, second.file, mine.file, "Recordings/10-28(수).m4a"] { try Data("audio".utf8).write(to: store.fileURL(path)) }
        let transcript = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "매칭")])
        for r in [old, trimmed] { try store.saveTranscript(transcript, of: r) }
        try ctx.edit(Harness.graphTheory) { $0.recordings = [old, second, trimmed, mine] }
    }

    @Test func retitleMatchesTheAction() throws {
        try h.expectSame(["recording", "retitle", "EC4207", "--yes"], prepare: { try record($0) }) { _ in
            RecordingRetitleLegacy(course: Harness.graphTheory)
        }
    }

    @Test func retitleRenamesOldRecordingsAndUndoTurnsThemBack() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist)
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device)
        let store = try ctx.store(Harness.graphTheory)
        let files = { try Dictionary(uniqueKeysWithValues: h.file(GISTStore(url: gist)).recordings.map { ($0.id, $0.file) }) }
        let exists = { (path: String) in FileManager.default.fileExists(atPath: store.fileURL(path).path) }
        let before = try files()

        #expect(h.cli(["recording", "retitle", "--dry-run"], gist: gist).code == 0)
        #expect(try files() == before && exists("Recordings/9주차-1.m4a"))

        let r = h.cli(["recording", "retitle", "--yes"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let after = try files()
        #expect(after[Self.old] == "Recordings/10-28(수) 2.m4a" && after[Self.second] == "Recordings/10-28(수) 3.m4a")
        #expect(after[Self.trimmed] == "Recordings/10-28(수) 4.m4a" && after[Self.mine] == "Recordings/보강.m4a")
        #expect(exists("Recordings/10-28(수) 2.m4a") && exists("Recordings/10-28(수) 2.transcript.json"))
        #expect(exists("Recordings/10-28(수) 4.transcript.json") && !exists("Recordings/10-28(수) 4.m4a"))
        #expect(!exists("Recordings/9주차-1.m4a") && exists("Recordings/10-28(수).m4a"))
        #expect(h.cli(["recording", "retitle", "--yes"], gist: gist).out.contains("10-28") == false)

        let batch = try #require(try MoveJournal.records(in: gist).last { $0.undoOf == nil }?.batch)
        #expect(h.cli(["cleanup", "undo", batch.uuidString, "--yes"], gist: gist).code == 0)
        #expect(try files() == before)
        #expect(exists("Recordings/9주차-1.m4a") && exists("Recordings/9주차-1.transcript.json") && exists("Recordings/9주차-2.transcript.json"))
    }
}

struct SessionLinkViewedTests {
    let h = Harness()

    func record(_ url: URL) throws {
        #expect(h.cli(MaterialNoteStudyTests.track, gist: url).code == 0)
        #expect(h.cli(SessionCommandTests.add, gist: url).code == 0)
        let ctx = ActionContext(gist: GISTStore(url: url), device: h.device, now: h.now)
        let slides = try #require(try ctx.file(Harness.graphTheory).materials.first { $0.path == "Lectures/05_Matchings.pdf" }).id
        let r = Recording(
            device: h.device, at: h.now, sessionId: SessionCommandTests.id, file: "Recordings/10-28(수).m4a", duration: 300,
            pages: [
                PageVisit(at: 0, materialId: slides, page: 4), PageVisit(at: 2, materialId: slides, page: 6),
                PageVisit(at: 100, materialId: slides, page: 9),
            ])
        try ctx.edit(Harness.graphTheory) { $0.recordings = [r] }
    }

    @Test func linkViewedMatchesTheAction() throws {
        try h.expectSame(["session", "link-viewed", "EC4207/10-28"], prepare: record) { _ in
            SessionLinkViewed(course: Harness.graphTheory, session: SessionCommandTests.id)
        }
    }

    @Test func linkViewedAddsTheRangeAndKeepsALinkTheUserSet() throws {
        let gist = try Harness.fixtureCopy()
        try record(gist)
        #expect(h.cli(["session", "link-viewed", "EC4207/10-28"], gist: gist).code == 0)
        var file = try h.file(GISTStore(url: gist))
        let session = try #require(file.sessions.first { $0.id == SessionCommandTests.id })

        #expect(session.materials.map { [$0.firstPage, $0.lastPage] } == [[6, 9]])

        _ = h.cli(["material", "link", "EC4207/05_Matchings.pdf", "10-28", "--pages", "1-3"], gist: gist)
        #expect(h.cli(["session", "link-viewed", "EC4207/10-28"], gist: gist).code == 0)
        file = try h.file(GISTStore(url: gist))
        #expect(file.sessions.first { $0.id == SessionCommandTests.id }?.materials.map { [$0.firstPage, $0.lastPage] } == [[1, 3]])
    }
}
