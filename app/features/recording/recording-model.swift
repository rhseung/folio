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
    /// Pause and stop wait while the recorder starts or finishes.
    var settling: Bool { preparing || recorder.state == .stopping }
    var recentLines: [LectureTranscript.Line] { Array(recorder.lines.suffix(40)) }
    var course: LoadedCourse? { recorder.courseId.flatMap { workspace.course($0) } }
    var accent: CourseAccent { recorder.courseId.map { workspace.accent($0) } ?? CourseAccent.gray }
    var courseTitle: String { preparing ? String(localized: .recordingPreparing) : course?.title ?? recorder.title }
    /// Like a recent session in the course column: its rough note, else its review note, else the sessions list.
    var sessionLink: AppLink? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else { return nil }
        if let note = session.roughNoteId ?? session.reviewNoteId { return AppLink(.note, note) }
        return .course(course.id, page: .sessions)
    }
    var sessionName: String? {
        guard let course, let id = recorder.recording?.sessionId, let session = course.file.sessions.first(where: { $0.id == id }) else { return nil }
        return course.file.title(of: session, calendar: workspace.calendar)
    }
    var line: String {
        recorder.volatile.isEmpty ? (recorder.lines.last?.text ?? recorder.transcriptionNote ?? String(localized: .recordingListening)) : recorder.volatile
    }

    var context: TranscriptionContext? { recorder.context }
    var contextSummary: String {
        context.map(TranscriptionContextText.summary) ?? String(localized: .recordingContextReading)
    }
    /// Where lecture files are linked to sessions: the course's files.
    var materialsLink: AppLink? { course.map { .course($0.id, page: .materials) } }
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
        // Read before the page draws, not in `load`: whether there are lines sets its layout, which would otherwise
        // jump once it is up.
        transcript = store.transcript(of: recording)
    }

    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        if recording.hasAudio { player.load(store.fileURL(recording.file), expected: recording.duration) }
    }

    // MARK: Address

    /// `11/2(월) 다시 듣기`: the class's day, which tells a course's recordings apart, as the crumb and a tab name it.
    static func name(of recording: Recording, in file: CourseFile, calendar: Calendar) -> String {
        guard let session = recording.sessionId.flatMap({ id in file.sessions.first { $0.id == id } }) else { return String(localized: .recordingPage) }
        return String(localized: .recordingPageNamed(file.day(of: session, calendar: calendar)))
    }

    var name: String { courseFile.map { Self.name(of: recording, in: $0, calendar: workspace.calendar) } ?? String(localized: .recordingPage) }
    /// What the class covered, as the sessions page titles it; a recording of no class goes by when it started.
    var title: String {
        if let courseFile, let session { return courseFile.title(of: session, calendar: workspace.calendar) }
        return recording.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// The moment the address names, in whole seconds and, while playing, in steps of five: each step redraws the
    /// window around the page, and a tab let go of reopens within a few seconds of where it was.
    var moment: Int {
        let t = Int(player.time)
        return player.playing ? t / 5 * 5 : t
    }

    var viewedLink: AppLink { AppLink(.recording, recording.id, anchor: .time(moment)) }

    /// Where a link opened the player, for the transcript to show that line.
    private(set) var seekedTo: TimeInterval?

    /// A moment the page reported comes back as the window's link; seeking to it again would pull playback back to
    /// the last step.
    func follow(_ link: AppLink) {
        load()
        guard link.kind == .recording, link.id == recording.id, case .time(let t) = link.anchor, t != moment else { return }
        player.seek(TimeInterval(t))
        seekedTo = TimeInterval(t)
    }

    func jump(to seconds: TimeInterval) {
        player.seek(seconds)
        player.play()
    }

    func lineIndex(at seconds: TimeInterval) -> Int? { transcript?.lineIndex(at: seconds) }

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

    // MARK: Selection

    /// Transcript indices, like `shownLines`, so a search narrowing the list keeps what was picked before it.
    private(set) var selected: Set<Int> = []
    private var anchor: Int?

    /// A plain pick starts over from that line; extending covers the shown lines between the anchor and it, so the
    /// range is what the reader sees between the two clicks even while a search hides lines in between.
    func select(_ index: Int, extending: Bool) {
        guard extending, let anchor else {
            selected = [index]
            anchor = index
            return
        }
        let range = min(anchor, index)...max(anchor, index)
        selected = Set(shownLines.map(\.index).filter(range.contains))
    }

    func selectAll() {
        let shown = shownLines.map(\.index)
        selected = Set(shown)
        anchor = anchor ?? shown.first
    }

    var allSelected: Bool { shownLines.allSatisfy { selected.contains($0.index) } }

    /// A touch screen's range under way: a long press started it on a line, and a tap moves its other end, as ⇧-click
    /// does with a pointer.
    private(set) var ranging = false

    func hold(_ index: Int) {
        select(index, extending: false)
        ranging = true
    }

    func endRange() { ranging = false }

    var canCopy: Bool { !selected.isEmpty }
    /// The menu's 받아쓰기 복사: every line, whatever is picked.
    var transcriptText: String { transcript?.text ?? "" }
    var copyLabel: String {
        selected.isEmpty ? String(localized: .recordingCopy) : String(localized: .recordingCopyLines(selected.count))
    }
    /// In transcript order, whichever order the lines were picked in, and in the transcript's own text form.
    var copiedText: String {
        guard let transcript else { return "" }
        let lines = selected.sorted().filter(transcript.lines.indices.contains).map { transcript.lines[$0] }
        return LectureTranscript(locale: transcript.locale, lines: lines).text
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

    // MARK: Lecture pages

    /// The lecture page on screen as line `index` began, where it differs from the line before's: on every line,
    /// the same `p.12` down a whole slide's worth of sentences hid the turns. A search shows it on every line left.
    func page(at index: Int) -> PageVisit? {
        guard let lines = transcript?.lines, lines.indices.contains(index), let visit = listed.visit(at: lines[index].start) else { return nil }
        if query.isEmpty, index > 0, let before = listed.visit(at: lines[index - 1].start),
           before.materialId == visit.materialId, before.page == visit.page { return nil }
        return visit
    }

    func pageLabel(_ visit: PageVisit) -> String { String(localized: .recordingLinePage(visit.page ?? 0)) }

    func pageHelp(_ visit: PageVisit) -> String {
        let name = courseFile?.materials.first { $0.id == visit.materialId }.map { ($0.path as NSString).lastPathComponent } ?? ""
        return String(localized: .recordingLinePageHelp(name, visit.page ?? 0))
    }

    func pageLink(_ visit: PageVisit) -> AppLink { AppLink(.material, visit.materialId, anchor: visit.page.map { .page($0) }) }

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
    var materialsLink: AppLink { .course(courseId, page: .materials) }

    func loadContext() async {
        guard usedContext == nil, let file = courseFile, let session else { return }
        let (store, recording) = (store, listed)
        readContext = await Task.detached { store.transcriptionContext(file, session: session, recording: recording) }.value
    }

    func transcribe() { workspace.transcribe(recording, course: courseId) }
    func cancelTranscription() { workspace.transcriptions.cancel(recording.id) }
    func reloadTranscript() {
        transcript = store.transcript(of: recording)
        // A new transcription splits the audio into other lines; the old indices would pick unrelated text.
        selected = []
        anchor = nil
        ranging = false
    }

    func remove() {
        player.stop()
        workspace.deleteRecording(recording, course: courseId)
    }
}
