import FolioDomain
import FolioStorage
import Foundation
import Observation

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
        // 줄이 있는지가 배치를 정하므로 `load`가 아니라 페이지를 그리기 전에 읽는다. 그러지 않으면 페이지가 뜬 뒤
        // 배치가 한 번 뛴다.
        transcript = store.transcript(of: recording)
    }

    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        if recording.hasAudio { player.load(store.fileURL(recording.file), expected: recording.duration) }
    }

    // MARK: Address

    static func name(of recording: Recording, in file: CourseFile, calendar: Calendar) -> String {
        guard let session = recording.sessionId.flatMap({ id in file.sessions.first { $0.id == id } }) else {
            return String(localized: .recordingPage)
        }
        return String(localized: .recordingPageNamed(file.day(of: session, calendar: calendar)))
    }

    var name: String {
        courseFile.map { Self.name(of: recording, in: $0, calendar: workspace.calendar) } ?? String(localized: .recordingPage)
    }
    var title: String {
        if let courseFile, let session { return courseFile.title(of: session, calendar: workspace.calendar) }
        return recording.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    // 재생 중에는 5초 단위로 바꾼다. 바뀔 때마다 페이지 둘레의 창을 다시 그리고, 놓은 탭은 몇 초 안의 자리에서 다시
    // 열리면 충분하다.
    var moment: Int {
        let t = Int(player.time)
        return player.playing ? t / 5 * 5 : t
    }

    var viewedLink: AppLink { AppLink(.recording, recording.id, anchor: .time(moment)) }

    private(set) var seekedTo: TimeInterval?

    // 페이지가 알린 순간은 창의 링크로 돌아온다. 그 순간으로 다시 이동하면 재생이 마지막 단계로 끌려간다.
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
        recording.startedAt.formatted(date: .abbreviated, time: .shortened) + " · "
            + RecordingTime.label(recording.hasAudio ? player.duration : recording.duration)
    }
    var hasLines: Bool { !(transcript?.lines.isEmpty ?? true) }
    var current: Int? { transcript?.lineIndex(at: player.time) }

    // 검색이 다른 줄을 숨겨도 줄은 전체 받아쓰기의 인덱스를 유지한다. 그 인덱스가 스크롤 anchor다.
    var shownLines: [(index: Int, line: LectureTranscript.Line, bookmarked: Bool)] {
        let marked = Set(recording.bookmarks.compactMap { transcript?.lineIndex(at: $0) })
        return (transcript?.lines ?? []).enumerated()
            .filter { query.isEmpty || $0.element.text.localizedCaseInsensitiveContains(query) }
            .map { i, line in (i, line, marked.contains(i)) }
    }

    // MARK: Selection

    // 검색이 목록을 줄여도 그 전에 고른 것이 남도록 받아쓰기 인덱스로 둔다.
    private(set) var selected: Set<Int> = []
    private var anchor: Int?

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

    private(set) var ranging = false

    func hold(_ index: Int) {
        select(index, extending: false)
        ranging = true
    }

    func endRange() { ranging = false }

    var canCopy: Bool { !selected.isEmpty }
    var transcriptText: String { transcript?.text ?? "" }
    var copyLabel: String {
        selected.isEmpty ? String(localized: .recordingCopy) : String(localized: .recordingCopyLines(selected.count))
    }
    var copiedText: String {
        guard let transcript else { return "" }
        let lines = selected.sorted().filter(transcript.lines.indices.contains).map { transcript.lines[$0] }
        return LectureTranscript(locale: transcript.locale, lines: lines).text
    }

    var phase: TranscriptionPhase? { workspace.transcriptions.phase(of: recording.id) }
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

    func page(at index: Int) -> PageVisit? {
        guard let lines = transcript?.lines, lines.indices.contains(index), let visit = listed.visit(at: lines[index].start) else {
            return nil
        }
        if query.isEmpty, index > 0, let before = listed.visit(at: lines[index - 1].start),
            before.materialId == visit.materialId, before.page == visit.page
        {
            return nil
        }
        return visit
    }

    func pageLabel(_ visit: PageVisit) -> String { String(localized: .recordingLinePage(visit.page ?? 0)) }

    func pageHelp(_ visit: PageVisit) -> String {
        let name = courseFile?.materials.first { $0.id == visit.materialId }.map { ($0.path as NSString).lastPathComponent } ?? ""
        return String(localized: .recordingLinePageHelp(name, visit.page ?? 0))
    }

    func pageLink(_ visit: PageVisit) -> AppLink { AppLink(.material, visit.materialId, anchor: visit.page.map { .page($0) }) }

    // MARK: Transcription context

    private(set) var readContext: TranscriptionContext?
    private var courseFile: CourseFile? { workspace.course(courseId)?.file }
    // 녹음하는 동안 남긴 쪽은 목록의 녹음에 있다. 이 플레이어가 연 사본은 그보다 오래되었을 수 있다.
    private var listed: Recording { courseFile?.recordings.first { $0.id == recording.id } ?? recording }
    private var session: Session? { courseFile?.sessions.first { $0.id == recording.sessionId } }
    private var linkedContext: TranscriptionContext? {
        guard let file = courseFile, let session else { return nil }
        return file.transcriptionContext(for: session, recording: listed)
    }

    var showsContext: Bool { session != nil }
    var usedContext: TranscriptionContext? { transcript?.context }
    var shownContext: TranscriptionContext? { usedContext ?? readContext ?? linkedContext }
    var contextTermsRead: Bool { usedContext != nil || readContext != nil }
    var contextSummary: String { shownContext.map(TranscriptionContextText.summary) ?? "" }
    var contextNote: String? {
        guard usedContext == nil else { return nil }
        return String(localized: hasLines ? .recordingContextUnrecorded : .recordingContextUpcoming)
    }
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
        // 새 받아쓰기는 소리를 다른 줄로 나누므로, 이전 인덱스는 상관없는 글을 고르게 된다.
        selected = []
        anchor = nil
        ranging = false
    }

    func remove() {
        player.stop()
        workspace.deleteRecording(recording, course: courseId)
    }
}
