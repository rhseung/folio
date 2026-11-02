import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class RecordingBarModel {
    let workspace: Workspace

    init(workspace: Workspace) { self.workspace = workspace }

    var recorder: LectureRecorder { workspace.recorder }
    var recording: Bool { recorder.state == .recording }
    var preparing: Bool { recorder.state == .preparing }
    var recentLines: [LectureTranscript.Line] { Array(recorder.lines.suffix(40)) }
    var course: LoadedCourse? { recorder.courseId.flatMap { workspace.course($0) } }
    var accent: CourseAccent { recorder.courseId.map { workspace.accent($0) } ?? CourseAccent.gray }
    var courseTitle: String { preparing ? String(localized: .recordingPreparing) : course?.title ?? recorder.title }
    /// Like a recent session in the course column: its rough note, else its review note, else the sessions list.
    var sessionTarget: SearchTarget? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else { return nil }
        if let note = session.roughNoteId ?? session.reviewNoteId { return SearchTarget(courseId: course.id, section: .notes, noteId: note) }
        return SearchTarget(courseId: course.id, section: .sessions)
    }
    var sessionName: String? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else { return nil }
        return course.file.name(of: session)
    }
    var line: String {
        recorder.volatile.isEmpty ? (recorder.lines.last?.text ?? recorder.transcriptionNote ?? String(localized: .recordingListening)) : recorder.volatile
    }

    func toggle() {
        if recording { recorder.pause() } else { workspace.perform { try recorder.resume() } }
    }

    func stop() async { await workspace.stopRecording() }
}

@MainActor @Observable
final class RecordingPlayerModel {
    let workspace: Workspace
    let courseId: UUID
    let store: CourseStore
    let recording: Recording
    let player = AudioPlayback()
    var transcript: LectureTranscript?
    var query = ""

    init(workspace: Workspace, courseId: UUID, store: CourseStore, recording: Recording) {
        self.workspace = workspace
        self.courseId = courseId
        self.store = store
        self.recording = recording
        // Read before the sheet opens, not in `load`: whether there are lines sets the sheet's height, which would
        // otherwise jump once it is up.
        transcript = store.transcript(of: recording)
    }

    func load() {
        if recording.hasAudio { player.load(store.fileURL(recording.file)) }
    }

    var subtitle: String {
        recording.startedAt.formatted(date: .abbreviated, time: .shortened) + " · " + RecordingTime.label(recording.hasAudio ? player.duration : recording.duration)
    }
    var hasLines: Bool { !(transcript?.lines.isEmpty ?? true) }
    var current: Int? { transcript?.lineIndex(at: player.time) }

    /// A line keeps its index in the whole transcript even when a search hides others: the index is its scroll anchor.
    var shownLines: [(index: Int, line: LectureTranscript.Line, bookmarked: Bool)] {
        (transcript?.lines ?? []).enumerated()
            .filter { query.isEmpty || $0.element.text.localizedCaseInsensitiveContains(query) }
            .map { i, line in (i, line, recording.bookmarks.contains { line.start <= $0 && $0 < line.end + 1 }) }
    }

    func remove() {
        player.stop()
        workspace.deleteRecording(recording, course: courseId)
    }
}
