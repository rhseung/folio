import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class SessionSheetModel {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var included = true
        var started = true
        var first: Int?
        var last: Int?

        var range: PageRange {
            get { PageRange(first: first, last: last) }
            set {
                first = newValue.first
                last = newValue.last
            }
        }
    }

    let workspace: Workspace
    let courseId: UUID
    let sessionId: UUID?
    let viewed: [SessionMaterial]
    let recorded: Bool
    private(set) var rows: [Row] = []
    private(set) var pageCounts: [UUID: Int] = [:]
    // 칸을 건드린 뒤에는 늦게 온 쪽 수가 사용자가 고친 제안을 다시 만들지 않는다.
    private var edited = false
    private let initial: (units: [UUID], attendance: AttendanceState, review: ClassReview?)

    var units: [UUID]
    var attendance: AttendanceState
    var review: ClassReview?
    // 노트 이름이 단원을 따르므로, 러프 노트는 저장할 때 단원을 쓴 뒤에 만든다.
    var makesNote = false

    var start: Date
    // 시작한 날 자정부터 센 분이다. 수업은 시작한 날에 끝난다.
    var endMinute: Int
    var link: String
    private(set) var kind: Session.Kind
    private var kindPicked = false
    // 끝 시각은 사용자가 고르거나 수업이 시간표 밖으로 옮길 때만 저장한다. 그 밖에는 시간표 칸이 계속 주므로, 나중에
    // 수업 시간을 고치면 끝 시각도 따라간다.
    private var endPicked = false

    convenience init(workspace: Workspace, request: SessionSheetRequest) {
        self.init(
            workspace: workspace, course: request.course, session: request.session, start: request.start,
            viewed: request.viewed, recorded: request.recorded)
    }

    init(workspace: Workspace, course: UUID, session: UUID?, start: Date? = nil, viewed: [SessionMaterial] = [], recorded: Bool = false) {
        self.workspace = workspace
        courseId = course
        sessionId = session
        self.recorded = recorded
        let file = workspace.course(course)?.file
        let s = session.flatMap { id in file?.sessions.first { $0.id == id } }
        // 방금 멈춘 녹음은 아직 course.json에 없으므로 요청이 쪽을 넘긴다. 나중에 열면 회차의 녹음이 쪽을 가진다.
        self.viewed = viewed.isEmpty ? file.flatMap { f in s.map { f.viewedPages(of: $0) } } ?? [] : viewed
        // 모든 저장 속성을 정하기 전에는 관찰되는 속성을 읽을 수 없으므로 지역 변수에서 읽는다. 출석은 항목 없음으로
        // 저장하므로, 항목이 없는 수업은 녹음 여부와 상관없이 출석으로 시작한다.
        let initial = (
            units: s?.unitIds ?? [],
            attendance: s.flatMap { s in file?.attendance.first { $0.sessionId == s.id }?.state } ?? AttendanceState.present,
            review: s.flatMap { file?.review(of: $0) }
        )
        units = initial.units
        attendance = initial.attendance
        review = initial.review
        self.initial = initial

        let calendar = workspace.calendar
        let begin = s?.date ?? start ?? calendar.date(byAdding: .hour, value: 18, to: calendar.startOfDay(for: workspace.now))!
        let schedule = file?.course.schedule ?? []
        let end = (s ?? Session(device: workspace.device, at: begin, week: 1, date: begin))
            .expectedEnd(schedule: schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
        self.start = begin
        endMinute = Self.minute(of: end, from: begin, calendar: calendar)
        link = s?.link ?? ""
        kind = s?.kind ?? .lecture
        if s == nil { kind = guessedKind(at: begin) }
        suggest()
    }

    var changed: Bool {
        if edited || makesNote || units != initial.units || attendance != initial.attendance || review != initial.review { return true }
        guard let session else { return false }
        return start != session.date || endPatch(session) != .keep || storedLink != session.link || kind != session.kind
    }

    private var course: LoadedCourse? { workspace.course(courseId) }
    private var file: CourseFile? { course?.file }
    private var session: Session? { sessionId.flatMap { id in file?.sessions.first { $0.id == id } } }
    var calendar: Calendar { workspace.calendar }
    var isAdding: Bool { sessionId == nil }

    var accent: CourseAccent { workspace.accent(courseId) }

    var title: String {
        guard let file, let session else { return String(localized: .sessionsAdd) }
        return String(localized: .sessionSheetTitle(file.course.title, file.day(of: session, calendar: calendar)))
    }

    var confirm: String { String(localized: isAdding ? .commonAdd : .commonSave) }

    // MARK: Sections

    // 수업이 시작했는지는 저장된 수업에서 읽는다. 그래야 시트에서 날짜를 옮겨도 포인터 아래에서 순서가 바뀌지 않는다.
    var sections: [SessionSection] {
        file?.sections(of: session, kind: kind, start: session?.date ?? start, at: workspace.now, takesAttendance: takesAttendance) ?? [
            .info
        ]
    }

    func label(_ section: SessionSection) -> String {
        switch section {
        case .progress: String(localized: .wrapUpProgress)
        case .units: String(localized: .wrapUpUnits)
        case .notes: String(localized: .sessionSheetNotes)
        case .attendance: String(localized: .sessionSheetAttendance)
        case .info: String(localized: .sessionSheetInfo)
        }
    }

    // MARK: Progress

    private func suggest() {
        guard let file, let session else { return }
        let wrappingUp = file.isWrappingUp(
            session, recorded: recorded, at: workspace.now,
            classMinutes: workspace.settings.classMinutes, calendar: calendar)
        rows = file.suggestedProgress(for: session, viewed: viewed, pageCounts: pageCounts)
            .map { range in
                let checked = session.wrapUpChecks(range, wrappingUp: wrappingUp)
                return Row(id: range.materialId, included: checked, started: checked, first: range.firstPage, last: range.lastPage)
            }
    }

    func load() async {
        guard let file else { return }
        var counts: [UUID: Int] = [:]
        // 렉처를 모두 읽으면 iCloud에서 하나하나 내려받으므로 목록의 파일만 읽는다.
        for m in file.materials where rows.contains(where: { $0.id == m.id }) {
            if let n = await workspace.pageCount(of: m, course: courseId) { counts[m.id] = n }
        }
        pageCounts = counts
        if !edited { suggest() }
    }

    func name(_ id: UUID) -> String {
        file?.materials.first { $0.id == id }.map { ($0.path as NSString).lastPathComponent } ?? ""
    }

    func taught(_ id: UUID) -> [PageRangeField.Taught] {
        guard let file, let sessionId else { return [] }
        return PageRangeField.Taught.list(file, material: id, besides: sessionId, calendar: calendar)
    }

    func zones(_ id: UUID) -> [PageRangeField.Section] {
        guard let file else { return [] }
        return PageRangeField.Section.list(file, material: id, pageCount: pageCounts[id])
    }

    func seen(_ id: UUID) -> ClosedRange<Int>? { viewed.first { $0.materialId == id }?.pages }

    var addable: [FolioDomain.Material] {
        (file?.lectureFiles ?? []).filter { m in !rows.contains { $0.id == m.id } }
    }

    func add(_ id: UUID) {
        edited = true
        guard let file, let session else { return }
        let range = file.suggestedRange(of: id, for: session, seen: viewed.first { $0.materialId == id }, pageCount: nil)
        rows.append(Row(id: id, first: range.firstPage, last: range.lastPage))

        guard let m = file.materials.first(where: { $0.id == id }) else { return }
        Task {
            if let n = await workspace.pageCount(of: m, course: courseId) {
                pageCounts[id] = n
                change(id) { row in row.range = row.range.moving(.first, to: row.first, pages: n) }
            }
        }
    }

    func toggle(_ id: UUID) { change(id) { $0.included.toggle() } }

    func setRange(_ id: UUID, _ range: PageRange) {
        change(id) { row in
            row.range = range
            row.included = true
        }
    }

    private func change(_ id: UUID, _ edit: (inout Row) -> Void) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        edited = true
        edit(&rows[i])
    }

    // MARK: Units

    var unitOptions: [PickOption<UUID>] {
        guard let file else { return [] }
        return UnitTree.outline(file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }

    var linkedUnits: [FolioDomain.Unit] {
        guard let file else { return [] }
        return UnitTree.outline(file.units).map(\.unit).filter { units.contains($0.id) }
    }

    func removeUnit(_ unit: UUID) { units.removeAll { $0 == unit } }

    func pick(_ unit: UUID) {
        if units.contains(unit) { units.removeAll { $0 == unit } } else { units.append(unit) }
    }

    func makeUnit(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = workspace.run(UnitAdd(course: courseId, title: title))?.made else { return }
        units.append(id)
    }

    // MARK: Notes

    var hasNote: Bool { linkedNote != nil }

    var linkedNote: NoteEntry? { note(session?.roughNoteId) }

    private func note(_ id: UUID?) -> NoteEntry? {
        guard let file, let id else { return nil }
        return file.notes.first { $0.id == id }
    }

    var noteChoices: [NoteEntry] { file?.classNoteChoices ?? [] }

    func noteName(_ note: NoteEntry) -> String { ((note.path as NSString).lastPathComponent as NSString).deletingPathExtension }

    func linkNote(_ id: UUID) {
        guard let sessionId else { return }
        // `NoteLink`는 이미 러프 노트를 가진 수업을 거절하므로, 가진 노트를 먼저 뗀다. 수업이 시트에 열려 있으니 있고
        // 휴강도 아니어서, 여기서 링크를 거절할 다른 이유는 없다.
        if let held = linkedNote, held.id != id { unlinkNote() }
        workspace.run(NoteLink(course: courseId, note: id, kind: .rough, session: sessionId, exam: nil, units: [], math: nil))
        makesNote = false
    }

    func unlinkNote() {
        guard let note = linkedNote, let sessionId else { return }
        workspace.run(NoteUnlinkSession(course: courseId, note: note.id, session: sessionId))
    }

    func makeNewNote() {
        unlinkNote()
        makesNote = !hasNote
    }

    var showsReview: Bool { review != nil && (session.map { $0.date <= workspace.now } ?? false) }

    func reviewLabel(_ review: ClassReview) -> String {
        switch review {
        case .needed: String(localized: .sessionSheetReviewNeeded)
        case .notNeeded: String(localized: .sessionSheetReviewNotNeeded)
        case .writing: String(localized: .sessionSheetReviewWriting)
        case .written: String(localized: .sessionSheetReviewWritten)
        }
    }

    // MARK: Attendance

    var takesAttendance: Bool {
        if let sessionId { return workspace.can(AttendanceSet(course: courseId, session: sessionId, state: .absent)) }
        return workspace.can(SessionAdd(course: courseId, date: start, attendance: .absent))
    }

    // MARK: When and how

    var kindOptions: [(Session.Kind, String)] { Session.Kind.options }

    func setKind(_ kind: Session.Kind) {
        self.kind = kind
        kindPicked = true
    }

    private func guessedKind(at date: Date) -> Session.Kind {
        !schedule.isEmpty && slot(at: date) == nil ? .makeup : .lecture
    }

    var end: Date { calendar.date(byAdding: .minute, value: endMinute, to: calendar.startOfDay(for: start))! }

    private var schedule: [ClassTime] { file?.course.schedule ?? [] }

    private func slot(at date: Date) -> ClassTime? {
        Session(device: workspace.device, at: date, week: 1, date: date).slot(in: schedule, calendar: calendar)
    }

    func setStart(_ date: Date) {
        let length = end.timeIntervalSince(start)
        start = date
        if isAdding && !kindPicked { kind = guessedKind(at: date) }
        if !endPicked, let slot = slot(at: date) {
            endMinute = slot.endMinute
        } else {
            endMinute = Self.minute(of: date.addingTimeInterval(length), from: date, calendar: calendar)
        }
    }

    func setEnd(_ minute: Int) {
        endMinute = minute
        endPicked = true
    }

    private var storedLink: String? { OnlineLink.stored(link) }

    private func endPatch(_ session: Session) -> Patch<Date?> {
        if endPicked { return .set(end) }
        guard start != session.date else { return .keep }
        return slot(at: start) != nil || session.end(schedule: schedule, calendar: calendar) != nil ? .set(end) : .keep
    }

    private func movesWeek(_ session: Session, _ file: CourseFile) -> Bool {
        start != session.date
            && file.week(of: start, moving: session.id, termStart: workspace.semester(of: file.course)?.start, calendar: calendar)
                != session.week
    }

    private static func minute(of date: Date, from start: Date, calendar: Calendar) -> Int {
        let minutes = Int(date.timeIntervalSince(calendar.startOfDay(for: start)) / 60)
        return min(max(minutes, 0), 24 * 60 - 5)
    }

    // MARK: Saving

    private func shows(_ section: SessionSection) -> Bool { sections.contains(section) }

    private var keptRows: [Row] { shows(.progress) ? rows.filter(\.included) : [] }

    var ranges: [SessionMaterial] {
        let kept = keptRows.map { SessionMaterial(materialId: $0.id, firstPage: $0.first, lastPage: $0.last) }
        return session?.changedRanges(kept) ?? kept
    }

    var unlinked: [UUID] {
        guard shows(.progress), let session else { return [] }
        return session.droppedLinks(started: Set(rows.filter(\.started).map(\.id)), kept: Set(keptRows.map(\.id)))
    }

    // 모든 묶음을 한 액션으로 저장하므로, 규칙이 한 부분을 거절하면 나머지도 쓰지 않는다.
    var action: any Action {
        guard let session else {
            return SessionAdd(
                course: courseId, date: start, end: end, link: storedLink, kind: kind,
                attendance: shows(.attendance) && attendance != .present ? attendance : nil,
                units: shows(.units) ? units : [])
        }
        let review = showsReview && shows(.notes) && review != initial.review ? review : nil
        return SessionWrapUp(
            course: courseId, session: session.id, ranges: ranges, unlinked: unlinked,
            units: shows(.units) ? .set(units) : .keep,
            attendance: shows(.attendance) ? .set(attendance) : .keep,
            date: start == session.date ? .keep : .set(start),
            end: endPatch(session),
            link: storedLink == session.link ? .keep : .set(storedLink),
            kind: kind == session.kind ? .keep : .set(kind),
            skipsReview: review?.skipsReview.map(Patch.set) ?? .keep,
            reviewUnfinished: review?.reviewUnfinished.map(Patch.set) ?? .keep,
            // 녹음이 아직 course.json에 없을 수 있으므로, 시트가 열릴 때의 상태로 정리 여부를 정한다.
            recorded: recorded)
    }

    var refusal: String? {
        if let row = keptRows.first(where: { $0.first == nil || $0.last == nil }) {
            let name = name(row.id)
            switch (row.first, row.last) {
            case (_?, nil): return String(localized: .sessionsProgressMissingLast(name))
            case (nil, _?): return String(localized: .sessionsProgressMissingFirst(name))
            default: return String(localized: .sessionsProgressMissingRange(name))
            }
        }
        return workspace.refusal(action)
    }

    var disabled: Bool { refusal != nil }

    var note: String? {
        if let refusal { return refusal }
        if let session, let file, movesWeek(session, file) { return String(localized: .sessionsRenameOnMove) }
        return nil
    }

    @discardableResult func submit() -> Bool {
        guard let result = workspace.run(action) else { return false }
        // 노트 이름이 수업 날짜와 단원을 따르도록 단원을 저장한 뒤에 만든다.
        if makesNote && !hasNote, let id = sessionId ?? result.made { _ = workspace.note(.rough, of: id, in: courseId) }
        return true
    }
}
