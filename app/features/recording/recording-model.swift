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
    var paused: Bool { recorder.state == .paused }
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

    var context: TranscriptionContext? { recorder.context }
    var contextSummary: String {
        context.map(TranscriptionContextText.summary) ?? String(localized: .recordingContextReading)
    }
    /// Where lecture files are linked to sessions: the course's files.
    var materialsTarget: SearchTarget? { course.map { SearchTarget(courseId: $0.id, section: .materials) } }
    func retellCaptionsIfChanged() { workspace.retellCaptionsIfChanged() }

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
        // A mark between two sentences goes on the one before it, as the line playing at that moment; matched by each
        // line's own span, a mark in a pause showed nowhere.
        let marked = Set(recording.bookmarks.compactMap { transcript?.lineIndex(at: $0) })
        return (transcript?.lines ?? []).enumerated()
            .filter { query.isEmpty || $0.element.text.localizedCaseInsensitiveContains(query) }
            .map { i, line in (i, line, marked.contains(i)) }
    }

    var phase: TranscriptionPhase? { workspace.transcriptions.phase(of: recording.id) }
    /// Still being recorded or moved into the course folder, there is no audio in place to read or delete yet.
    private var settling: Bool { workspace.recorder.current == recording.id || workspace.finishingRecordings.contains(recording.id) }
    var canTranscribe: Bool { recording.hasAudio && phase == nil && !settling }
    var removalRefusal: String? { settling ? String(localized: .recordingRemoveBusy) : nil }

    var phaseLabel: String {
        switch phase {
        case .waiting: String(localized: .recordingTranscribeWaiting)
        case .downloading(let f): String(localized: .recordingTranscribeDownloading(Int(f * 100)))
        case .preparing: String(localized: .recordingTranscribePreparing)
        case .transcribing(let f): String(localized: .recordingTranscribeProgress(Int(f * 100)))
        case nil: ""
        }
    }
    var phaseFraction: Double? {
        switch phase {
        case .downloading(let f), .transcribing(let f): f
        case .waiting, .preparing, nil: nil
        }
    }

    var bookmarks: [TimeInterval] { recording.bookmarks.sorted() }

    // MARK: Transcription context

    /// Made from the course as it is, terms read from the slides; only for a transcript that kept no context.
    private(set) var readContext: TranscriptionContext?
    private var courseFile: CourseFile? { workspace.course(courseId)?.file }
    /// The listed one has the pages kept while recording; the copy this player opened with may predate them.
    private var listed: Recording { courseFile?.recordings.first { $0.id == recording.id } ?? recording }
    private var session: Session? { courseFile?.sessions.first { $0.id == recording.sessionId } }
    /// The course's links now, terms left out: what a transcription started now would be told.
    private var linkedContext: TranscriptionContext? {
        guard let file = courseFile, let session else { return nil }
        return file.transcriptionContext(for: session, recording: listed)
    }

    /// Only a recording of a session has slides and units to be told about.
    var showsContext: Bool { session != nil }
    var usedContext: TranscriptionContext? { transcript?.context }
    var shownContext: TranscriptionContext? { usedContext ?? readContext ?? linkedContext }
    var contextTermsRead: Bool { usedContext != nil || readContext != nil }
    var contextSummary: String { shownContext.map(TranscriptionContextText.summary) ?? "" }
    /// Said when what is shown is not what the transcript was told.
    var contextNote: String? {
        guard usedContext == nil else { return nil }
        return String(localized: hasLines ? .recordingContextUnrecorded : .recordingContextUpcoming)
    }
    /// The slides or units linked since would tell a new transcription something else.
    var contextChanged: Bool {
        guard hasLines, let used = usedContext, let now = linkedContext else { return false }
        return used.differs(from: now)
    }
    var materialsTarget: SearchTarget { SearchTarget(courseId: courseId, section: .materials) }

    func loadContext() async {
        guard usedContext == nil, let file = courseFile, let session else { return }
        let (store, recording) = (store, listed)
        readContext = await Task.detached { store.transcriptionContext(file, session: session, recording: recording) }.value
    }

    func transcribe() { workspace.transcribe(recording, course: courseId) }
    func cancelTranscription() { workspace.transcriptions.cancel(recording.id) }
    func reloadTranscript() { transcript = store.transcript(of: recording) }

    func remove() {
        player.stop()
        workspace.deleteRecording(recording, course: courseId)
    }
}
