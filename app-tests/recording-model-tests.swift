import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct RecordingPlayerModelTests {
    let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!

    func recorded(_ workspace: Workspace, bookmarks: [TimeInterval] = [], lines: [LectureTranscript.Line] = []) throws -> RecordingPlayerModel {
        let ctx = ActionContext(gist: try #require(workspace.gist), device: workspace.device, now: workspace.now)
        let store = try ctx.store(linearAlgebra)
        let recording = Recording(device: workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a", duration: 60, bookmarks: bookmarks)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: store.fileURL(recording.file))
        try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: lines), of: recording)
        try ctx.edit(linearAlgebra) { $0.recordings = [recording] }
        workspace.reload()
        return RecordingPlayerModel(workspace: workspace, courseId: linearAlgebra, store: store, recording: recording)
    }

    @Test func searchKeepsTranscriptIndicesAndMarksBookmarks() throws {
        let f = try QuizFixture()
        let recording = Recording(device: f.workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a", bookmarks: [10])
        let model = RecordingPlayerModel(workspace: f.workspace, courseId: f.courseId, store: f.course.store, recording: recording)
        model.transcript = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "그래프 정의"),
                                                                      .init(start: 5, end: 11, text: "트리"),
                                                                      .init(start: 11, end: 20, text: "그래프 탐색")])
        #expect(model.shownLines.map(\.bookmarked) == [false, true, false])
        model.query = "그래프"
        #expect(model.shownLines.map(\.index) == [0, 2])
        #expect(model.hasLines)
    }

    /// The sheet's height follows whether there are lines, so they must be known before it opens, not after `load`.
    @Test func readsTheTranscriptBeforeLoading() throws {
        let f = try QuizFixture()
        let heard = Recording(device: f.workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a")
        try f.course.store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "그래프 정의")]), of: heard)
        #expect(RecordingPlayerModel(workspace: f.workspace, courseId: f.courseId, store: f.course.store, recording: heard).hasLines)
        let silent = Recording(device: f.workspace.device, at: .now, sessionId: nil, file: "Recordings/b.m4a")
        #expect(!RecordingPlayerModel(workspace: f.workspace, courseId: f.courseId, store: f.course.store, recording: silent).hasLines)
    }

    @Test func aMarkInAPauseGoesOnTheLineBefore() throws {
        let model = try recorded(try fixtureWorkspace(), bookmarks: [12, 3], lines: [
            .init(start: 0, end: 5, text: "행렬"), .init(start: 20, end: 25, text: "고윳값"),
        ])
        #expect(model.shownLines.map(\.bookmarked) == [true, false])
        #expect(model.bookmarks == [3, 12])
    }

    @Test func aStoppedRecordingCanBeDeleted() throws {
        let workspace = try fixtureWorkspace()
        let model = try recorded(workspace)
        #expect(model.removalRefusal == nil && model.canTranscribe)
        model.remove()
        #expect(workspace.course(linearAlgebra)?.file.recordings.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: model.store.fileURL(model.recording.file).path))
        #expect(!FileManager.default.fileExists(atPath: model.store.fileURL(model.recording.transcriptFile).path))
    }

    @Test func aRecordingStillMovingIntoTheCourseIsKept() throws {
        let workspace = try fixtureWorkspace()
        let model = try recorded(workspace)
        workspace.finishingRecordings.insert(model.recording.id)
        #expect(model.removalRefusal != nil && !model.canTranscribe)
        model.remove()
        #expect(workspace.course(linearAlgebra)?.file.recordings.count == 1)
    }

    /// Needs a spoken file and this Mac's speech model, so it runs only when given one:
    /// `TEST_RUNNER_FOLIO_TRANSCRIBE_AUDIO=<m4a of Korean speech>`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_TRANSCRIBE_AUDIO"] != nil))
    func aRecordingWithoutCaptionsIsTranscribedFromItsAudio() async throws {
        let workspace = try fixtureWorkspace()
        let model = try recorded(workspace)
        let audio = URL(filePath: try #require(ProcessInfo.processInfo.environment["FOLIO_TRANSCRIBE_AUDIO"]))
        try FileManager.default.removeItem(at: model.store.fileURL(model.recording.file))
        try FileManager.default.copyItem(at: audio, to: model.store.fileURL(model.recording.file))
        #expect(!model.hasLines)
        workspace.transcribe(model.recording, course: linearAlgebra, engine: .apple)
        #expect(model.phase != nil)
        while model.phase != nil { try await Task.sleep(for: .milliseconds(200)) }
        #expect(workspace.error == nil)
        model.reloadTranscript()
        #expect(model.transcript?.text.contains("컴파일러") == true)
    }

    @Test func whispersFillersAreDroppedButSpeechIsKept() {
        #expect(WhisperTranscriber.isFiller("감사합니다."))
        #expect(WhisperTranscriber.isFiller(" 시청해 주셔서 감사합니다!"))
        #expect(WhisperTranscriber.isFiller("Thank you."))
        #expect(!WhisperTranscriber.isFiller("들어 주셔서 감사합니다. 다음 시간에는 LR 파서를 봅니다."))
    }
}

@MainActor
struct RecordingBarModelTests {
    /// Like the course column's recent sessions: the rough note, else the review note, else the sessions list.
    @Test func theSessionOpensItsNoteElseTheSessionsList() throws {
        let workspace = try fixtureWorkspace()
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a")
        workspace.recorder.stage(recording, course: graphTheory, title: "그래프 이론")
        let model = RecordingBarModel(workspace: workspace)
        #expect(model.sessionTarget == SearchTarget(courseId: graphTheory, section: .sessions))

        let review = try #require(workspace.run(SessionNote(course: graphTheory, session: session, kind: .review))?.made)
        #expect(model.sessionTarget == SearchTarget(courseId: graphTheory, section: .notes, noteId: review))
        let rough = try #require(workspace.run(SessionNote(course: graphTheory, session: session, kind: .rough))?.made)
        #expect(model.sessionTarget == SearchTarget(courseId: graphTheory, section: .notes, noteId: rough))
    }
}

private actor Overlap {
    private var running = 0
    private(set) var most = 0
    private(set) var runs = 0
    func enter() { running += 1; runs += 1; most = max(most, running) }
    func leave() { running -= 1 }
}

@MainActor
struct TranscriptionQueueTests {
    @Test func aCancelledJobIsNotOverlappedByTheOneAskedForAgain() async throws {
        let queue = TranscriptionQueue()
        let overlap = Overlap()
        let id = UUID()
        // Like Whisper mid-window: it notices the cancel only when its current step ends.
        let work: @Sendable (@escaping @Sendable (TranscriptionPhase) -> Void) async throws -> Void = { _ in
            await overlap.enter()
            let until = ContinuousClock.now + .milliseconds(200)
            while ContinuousClock.now < until { await Task.yield() }
            await overlap.leave()
        }
        queue.run(id, failed: { _ in }, work)
        try await Task.sleep(for: .milliseconds(50))
        queue.cancel(id)
        #expect(queue.phase(of: id) == nil)
        queue.run(id, failed: { _ in }, work)
        #expect(queue.phase(of: id) == .waiting)
        let deadline = ContinuousClock.now + .seconds(5)
        while queue.phase(of: id) != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(queue.phase(of: id) == nil)
        #expect(await overlap.runs == 2)
        #expect(await overlap.most == 1)
    }

    @Test func askingAgainForAQueuedRecordingDoesNothing() async throws {
        let queue = TranscriptionQueue()
        let overlap = Overlap()
        let id = UUID()
        let work: @Sendable (@escaping @Sendable (TranscriptionPhase) -> Void) async throws -> Void = { _ in
            await overlap.enter()
            try? await Task.sleep(for: .milliseconds(100))
            await overlap.leave()
        }
        queue.run(id, failed: { _ in }, work)
        queue.run(id, failed: { _ in }, work)
        let deadline = ContinuousClock.now + .seconds(5)
        while queue.phase(of: id) != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await overlap.runs == 1)
    }
}
