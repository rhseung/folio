@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct RecordingTrimTests {
    let h = Harness()
    static let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
    static let heard = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E1")!
    static let silent = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E2")!

    /// Two recordings in the finished spring semester: one with a transcript, one without. Recordings are made by the
    /// recorder, not by an action, so they are written here.
    func record(_ gist: URL, course: UUID = linearAlgebra) throws {
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        let store = try ctx.store(course)
        let heard = Recording(id: Self.heard, device: h.device, at: h.now, sessionId: nil, file: "Recordings/1주차-1.m4a", duration: 60)
        let silent = Recording(id: Self.silent, device: h.device, at: h.now, sessionId: nil, file: "Recordings/1주차-2.m4a", duration: 60)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        for r in [heard, silent] { try Data("audio".utf8).write(to: store.fileURL(r.file)) }
        try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "행렬")]), of: heard)
        try ctx.edit(course) { $0.recordings = [heard, silent] }
    }

    @Test func trimMatchesTheAction() throws {
        try h.expectSame(["recording", "trim", "2026-1", "--yes"], prepare: { try record($0) }) { gist in
            RecordingTrim(semester: try #require(try ActionContext(gist: gist, device: h.device).file(Self.linearAlgebra).course.semesterId))
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
