import FolioActions
import FolioDomain
import Foundation
import Observation

/// What opens a class's sheet, from wherever it is asked: a menu's 편집…, the units icon, a stopped recording, Today's
/// wrap-up card. `session` nil adds a class, at `start` when a timetable slot gives one.
struct SessionSheetRequest: Identifiable {
    let id = UUID()
    let course: UUID
    var session: UUID?
    var start: Date?
    /// The group to scroll to, for a shortcut into one part (the card's units icon).
    var focus: SessionSection?
    /// The pages a recording just stopped stayed on, which a recording not saved yet can't give.
    var viewed: [SessionMaterial] = []
    /// A recording of the class has just stopped and isn't saved yet: the class was attended.
    var recorded = false
    /// Asked for rather than opened (a stopped recording, Today's card, a run through past classes): closing it is
    /// "나중에", not "취소".
    var asked = false
}

/// A class's one sheet (#403): what it covered (progress, units), its notes and review, its attendance, and when and
/// how it meets. A plain form (2026-11-08): every field holds what the class has or the suggestion for it, and saving
/// writes what differs in one action. Saving a class that is over, or recorded, wraps it up (`CourseFile.savingWrapsUp`).
@MainActor @Observable
final class SessionSheetModel {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var included = true
        /// Checked when the sheet opened: only such a row of a file the class links drops the link when unchecked.
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
    /// Nil while adding.
    let sessionId: UUID?
    let viewed: [SessionMaterial]
    let recorded: Bool
    private(set) var rows: [Row] = []
    private(set) var pageCounts: [UUID: Int] = [:]
    /// Once a field is touched, counts arriving late no longer redo the suggestion under the user's hands.
    private var edited = false
    /// What the class had when the sheet opened, so leaving for the split screen asks only when something would be lost.
    private let initial: (units: [UUID], attendance: AttendanceState, review: ClassReview?)

    var units: [UUID]
    var attendance: AttendanceState
    var review: ClassReview?
    /// The class's rough note is made on saving, after the units are, so the note is named after them.
    var makesNote = false

    var start: Date
    /// Minutes from the start day's midnight: a class ends on the day it starts. The view sets it through `setEnd`.
    var endMinute: Int
    var link: String
    /// While adding, follows the start until picked: a class off the timetable is most likely a makeup. Editing keeps
    /// the session's own kind until the user changes it.
    private(set) var kind: Session.Kind
    private var kindPicked = false
    /// The end is stored only when the user picks it or a class moves off the timetable; otherwise the slot keeps
    /// giving it, so editing the class times later still moves it.
    private var endPicked = false

    convenience init(workspace: Workspace, request: SessionSheetRequest) {
        self.init(workspace: workspace, course: request.course, session: request.session, start: request.start,
                  viewed: request.viewed, recorded: request.recorded)
    }

    init(workspace: Workspace, course: UUID, session: UUID?, start: Date? = nil, viewed: [SessionMaterial] = [], recorded: Bool = false) {
        self.workspace = workspace
        courseId = course
        sessionId = session
        self.recorded = recorded
        let file = workspace.course(course)?.file
        let s = session.flatMap { id in file?.sessions.first { $0.id == id } }
        // A recording just stopped isn't in course.json yet, so the ask passes its pages; opened later, the session's
        // recordings have them.
        self.viewed = viewed.isEmpty ? file.flatMap { f in s.map { f.viewedPages(of: $0) } } ?? [] : viewed
        // From locals: the observed properties can't be read back before every stored property is set.
        // Present is stored as no entry, so a class without one, recorded or not, starts on present.
        let initial = (units: s?.unitIds ?? [], attendance: s.flatMap { s in file?.attendance.first { $0.sessionId == s.id }?.state } ?? AttendanceState.present,
                       review: s.flatMap { file?.review(of: $0) })
        units = initial.units
        attendance = initial.attendance
        review = initial.review
        self.initial = initial

        let calendar = workspace.calendar
        let begin = s?.date ?? start ?? calendar.date(byAdding: .hour, value: 18, to: calendar.startOfDay(for: workspace.now))!
        let schedule = file?.course.schedule ?? []
        // A class being added has no session yet; a stand-in at its start asks the same question the join button does.
        let end = (s ?? Session(device: workspace.device, at: begin, week: 1, date: begin))
            .expectedEnd(schedule: schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
        self.start = begin
        endMinute = Self.minute(of: end, from: begin, calendar: calendar)
        link = s?.link ?? ""
        kind = s?.kind ?? .lecture
        if s == nil { kind = guessedKind(at: begin) }
        suggest()
    }

    /// Whether leaving would lose something, including the class's time, kind and link the sheet now holds too.
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

    /// The groups this class shows, in order. Whether the class has begun is read from the class as saved, so moving
    /// its date in the sheet doesn't reorder the sheet under the pointer.
    var sections: [SessionSection] {
        file?.sections(of: session, kind: kind, start: session?.date ?? start, at: workspace.now, takesAttendance: takesAttendance) ?? [.info]
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
        let wrappingUp = file.isWrappingUp(session, recorded: recorded, at: workspace.now,
                                           classMinutes: workspace.settings.classMinutes, calendar: calendar)
        rows = file.suggestedProgress(for: session, viewed: viewed, pageCounts: pageCounts)
            .map { range in
                let checked = session.wrapUpChecks(range, wrappingUp: wrappingUp)
                return Row(id: range.materialId, included: checked, started: checked, first: range.firstPage, last: range.lastPage)
            }
    }

    /// Counts tell where a file ends: the first page stays within it, and a finished file hands over to the next.
    func load() async {
        guard let file else { return }
        var counts: [UUID: Int] = [:]
        // Only the files listed: reading every lecture would download each from iCloud.
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

    /// The file's zones when its units split it (#321): the bar draws them, and the range reads as the units it reaches.
    func zones(_ id: UUID) -> [PageRangeField.Section] {
        guard let file else { return [] }
        return PageRangeField.Section.list(file, material: id, pageCount: pageCounts[id])
    }

    func seen(_ id: UUID) -> ClosedRange<Int>? { viewed.first { $0.materialId == id }?.pages }

    /// Lecture files not in the list yet.
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
                // The suggestion was made without the count; it stays within the file now that it's known.
                change(id) { row in row.range = row.range.moving(.first, to: row.first, pages: n) }
            }
        }
    }

    func toggle(_ id: UUID) { change(id) { $0.included.toggle() } }

    /// Picking pages on a bar left unchecked (a suggestion during the class) means to save them: the row is checked
    /// and from then on asks for both ends.
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

    /// Every unit of the course in outline order, none put forward: whether a unit is done, and which comes next, is
    /// the user's call (#147).
    var unitOptions: [PickOption<UUID>] {
        guard let file else { return [] }
        return UnitTree.outline(file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }

    /// The class's units as chips, in outline order rather than the order they were picked.
    var linkedUnits: [FolioDomain.Unit] {
        guard let file else { return [] }
        return UnitTree.outline(file.units).map(\.unit).filter { units.contains($0.id) }
    }

    func removeUnit(_ unit: UUID) { units.removeAll { $0 == unit } }

    func pick(_ unit: UUID) {
        if units.contains(unit) { units.removeAll { $0 == unit } } else { units.append(unit) }
    }

    /// Made at once: a new unit is a unit of the course whether or not this class is saved.
    func makeUnit(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = workspace.run(UnitAdd(course: courseId, title: title))?.made else { return }
        units.append(id)
    }

    // MARK: Notes

    var hasNote: Bool { linkedNote != nil }

    /// The class's own (rough) note. A review note also fills the gap, but it covers other classes too, so the row
    /// never swaps or unlinks it.
    var linkedNote: NoteEntry? { note(session?.roughNoteId) }

    private func note(_ id: UUID?) -> NoteEntry? {
        guard let file, let id else { return nil }
        return file.notes.first { $0.id == id }
    }

    var noteChoices: [NoteEntry] { file?.classNoteChoices ?? [] }

    func noteName(_ note: NoteEntry) -> String { ((note.path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// Written at once, as "새 단원" is (#147): the note exists already, so there is nothing to wait for.
    func linkNote(_ id: UUID) {
        guard let sessionId else { return }
        // `NoteLink` refuses a class that already holds a rough note, so the held one is taken off first. Nothing else
        // can refuse the link here: the class is open in its sheet, so it exists and isn't cancelled.
        if let held = linkedNote, held.id != id { unlinkNote() }
        workspace.run(NoteLink(course: courseId, note: id, kind: .rough, session: sessionId, exam: nil, units: [], math: nil))
        makesNote = false
    }

    /// Taken off at once, as linking writes at once; the note itself stays in the course.
    func unlinkNote() {
        guard let note = linkedNote, let sessionId else { return }
        workspace.run(NoteUnlinkSession(course: courseId, note: note.id, session: sessionId))
    }

    /// The linked note gives way now; the new one is made on saving, after the units, so they name it.
    func makeNewNote() {
        unlinkNote()
        makesNote = !hasNote
    }

    /// Asked only once the class has begun: ahead of it there is no review to keep or skip yet.
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

    /// A course without a timetable has no time off it, so nothing there reads as a makeup.
    private func guessedKind(at date: Date) -> Session.Kind {
        !schedule.isEmpty && slot(at: date) == nil ? .makeup : .lecture
    }

    var end: Date { calendar.date(byAdding: .minute, value: endMinute, to: calendar.startOfDay(for: start))! }

    private var schedule: [ClassTime] { file?.course.schedule ?? [] }

    private func slot(at date: Date) -> ClassTime? {
        Session(device: workspace.device, at: date, week: 1, date: date).slot(in: schedule, calendar: calendar)
    }

    /// Onto a timetable slot the class ends with the slot, unless an end was picked; elsewhere it keeps its length.
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

    /// Saves the end the form shows. Unmoved and unpicked, the end stays as it is. Moved, the form's end goes to the
    /// action, which drops it again when it is the new slot's own, so the slot keeps giving it; a class with no end
    /// at all (a date-only import) gets none.
    private func endPatch(_ session: Session) -> Patch<Date?> {
        if endPicked { return .set(end) }
        guard start != session.date else { return .keep }
        return slot(at: start) != nil || session.end(schedule: schedule, calendar: calendar) != nil ? .set(end) : .keep
    }

    private func movesWeek(_ session: Session, _ file: CourseFile) -> Bool {
        start != session.date
            && file.week(of: start, moving: session.id, termStart: workspace.semester(of: file.course)?.start, calendar: calendar) != session.week
    }

    private static func minute(of date: Date, from start: Date, calendar: Calendar) -> Int {
        let minutes = Int(date.timeIntervalSince(calendar.startOfDay(for: start)) / 60)
        return min(max(minutes, 0), 24 * 60 - 5)
    }

    // MARK: Saving

    private func shows(_ section: SessionSection) -> Bool { sections.contains(section) }

    /// No rows without lecture files: progress isn't shown then, and a file the class links whole would otherwise
    /// block saving from out of sight.
    private var keptRows: [Row] { shows(.progress) ? rows.filter(\.included) : [] }

    /// Only the ranges the class doesn't have already: every row starts on the class's own pages.
    var ranges: [SessionMaterial] {
        let kept = keptRows.map { SessionMaterial(materialId: $0.id, firstPage: $0.first, lastPage: $0.last) }
        return session?.changedRanges(kept) ?? kept
    }

    /// Files the class links whose rows were unchecked: the save takes them off, pages and all. None while progress
    /// is hidden, where no row could have been unchecked.
    var unlinked: [UUID] {
        guard shows(.progress), let session else { return [] }
        return session.droppedLinks(started: Set(rows.filter(\.started).map(\.id)), kept: Set(keptRows.map(\.id)))
    }

    /// The one action the sheet saves with: every group at once, so a part the rules refuse leaves the rest unwritten.
    /// Groups the sheet hides keep what the class has.
    var action: any Action {
        guard let session else {
            return SessionAdd(course: courseId, date: start, end: end, link: storedLink, kind: kind,
                              attendance: shows(.attendance) && attendance != .present ? attendance : nil,
                              units: shows(.units) ? units : [])
        }
        let review = showsReview && shows(.notes) && review != initial.review ? review : nil
        return SessionWrapUp(course: courseId, session: session.id, ranges: ranges, unlinked: unlinked,
                             units: shows(.units) ? .set(units) : .keep,
                             attendance: shows(.attendance) ? .set(attendance) : .keep,
                             date: start == session.date ? .keep : .set(start),
                             end: endPatch(session),
                             link: storedLink == session.link ? .keep : .set(storedLink),
                             kind: kind == session.kind ? .keep : .set(kind),
                             skipsReview: review?.skipsReview.map(Patch.set) ?? .keep,
                             reviewUnfinished: review?.reviewUnfinished.map(Patch.set) ?? .keep,
                             // The recording may not be in course.json yet: the save wraps up as the sheet opened.
                             recorded: recorded)
    }

    /// Why saving is off: a kept file without both pages says nothing about how far the class went.
    var refusal: String? {
        if let row = keptRows.first(where: { $0.first == nil || $0.last == nil }) {
            // Names the end the bar still lacks: the bar is picked on, not typed into, and its lone handle drags out
            // the missing end.
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

    /// Why 저장 is off, a row lacking an end included (2026-11-10): the lone handle and the dimmed button alone left
    /// the user unable to tell why the class couldn't be saved. Moving a class to another week renames it, which no
    /// field shows.
    var note: String? {
        if let refusal { return refusal }
        if let session, let file, movesWeek(session, file) { return String(localized: .sessionsRenameOnMove) }
        return nil
    }

    /// False when the save failed, so a run through several classes stays on this one.
    @discardableResult func submit() -> Bool {
        guard let result = workspace.run(action) else { return false }
        // After the units are saved, so the note is named by the class's day and units like any class note.
        if makesNote && !hasNote, let id = sessionId ?? result.made { _ = workspace.note(.rough, of: id, in: courseId) }
        return true
    }
}
