import FolioActions
import FolioDomain
import Foundation
import Observation

/// One class's wrap-up, asked when its recording stops, from the today screen, and from the class's menu. A plain form
/// (2026-11-08): every item shows as its control, holding what the class has or the suggestion for it, and saving
/// writes what differs in one action. What the class lacks (`CourseFile.wrapUpGaps`) only decides when to ask.
@MainActor @Observable
final class ClassWrapUpModel {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var included = true
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
    let sessionId: UUID
    let viewed: [SessionMaterial]
    /// A recording of the class has just stopped and isn't saved yet: the class was attended.
    let recorded: Bool
    private(set) var rows: [Row] = []
    private(set) var pageCounts: [UUID: Int] = [:]
    /// Once a field is touched, counts arriving late no longer redo the suggestion under the user's hands.
    private var edited = false
    /// What the class had when the sheet opened, so leaving for the split screen asks only when something would be lost.
    private let initial: (units: [UUID], attendance: AttendanceState)

    var units: [UUID]
    var attendance: AttendanceState
    /// The class's rough note is made on saving, after the units are, so the note is named after them.
    var makesNote = false
    var newUnit = ""
    /// Assignments added from the announcements line, to show they went in.
    private(set) var announced: [String] = []
    var addingExam: Exam?

    init(workspace: Workspace, course: UUID, session: UUID, viewed: [SessionMaterial] = [], recorded: Bool = false) {
        self.workspace = workspace
        courseId = course
        sessionId = session
        self.recorded = recorded
        let file = workspace.course(course)?.file
        let s = file?.sessions.first { $0.id == session }
        // A recording just stopped isn't in course.json yet, so the ask passes its pages; opened later, the session's
        // recordings have them.
        self.viewed = viewed.isEmpty ? file.flatMap { f in s.map { f.viewedPages(of: $0) } } ?? [] : viewed
        // From locals: the observed properties can't be read back before every stored property is set.
        // Present is stored as no entry, so a class without one, recorded or not, starts on present.
        let initial = (units: s?.unitIds ?? [], attendance: file?.attendance.first { $0.sessionId == session }?.state ?? AttendanceState.present)
        units = initial.units
        attendance = initial.attendance
        self.initial = initial
        suggest()
    }

    var changed: Bool {
        edited || makesNote || units != initial.units || attendance != initial.attendance
    }

    var course: LoadedCourse? { workspace.course(courseId) }
    private var file: CourseFile? { course?.file }
    private var session: Session? { file?.sessions.first { $0.id == sessionId } }

    var accent: CourseAccent { workspace.accent(courseId) }
    var courseTitle: String { course?.title ?? "" }

    var title: String {
        guard let file, let session else { return String(localized: .wrapUpTitle) }
        return String(localized: .wrapUpTitleOf(file.course.title, file.day(of: session, calendar: workspace.calendar)))
    }

    // MARK: Items

    /// Every item this class can be asked about, in asking order: progress only for a course with lecture files, and
    /// attendance only where it can be written.
    var items: [WrapUpItem] {
        WrapUpItem.allCases.filter { item in
            switch item {
            case .progress: !(file?.lectureFiles.isEmpty ?? true)
            case .attendance: takesAttendance
            default: true
            }
        }
    }

    func label(_ item: WrapUpItem) -> String { item.label }

    // MARK: Progress

    private func suggest() {
        guard let file, let session else { return }
        rows = file.suggestedProgress(for: session, viewed: viewed, pageCounts: pageCounts)
            .map { Row(id: $0.materialId, included: session.wrapUpChecks($0), first: $0.firstPage, last: $0.lastPage) }
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
        guard let file else { return [] }
        return PageRangeField.Taught.list(file, material: id, besides: sessionId, calendar: workspace.calendar)
    }

    /// The file's zones when its units split it (#321): the bar draws them, and the range reads as the units it reaches.
    func sections(_ id: UUID) -> [PageRangeField.Section] {
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
    func setRange(_ id: UUID, _ range: PageRange) { change(id) { $0.range = range } }

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
    func addUnit() {
        let title = newUnit.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = workspace.run(UnitAdd(course: courseId, title: title))?.made else { return }
        units.append(id)
        newUnit = ""
    }

    // MARK: Note

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
        // `NoteLink` refuses a class that already holds a rough note, so the held one is taken off first. Nothing else
        // can refuse the link here: the class is open in a wrap-up, so it exists and isn't cancelled.
        if let held = linkedNote, held.id != id { unlinkNote() }
        workspace.run(NoteLink(course: courseId, note: id, kind: .rough, session: sessionId, exam: nil, units: [], math: nil))
        makesNote = false
    }

    /// Taken off at once, as linking writes at once; the note itself stays in the course.
    func unlinkNote() {
        guard let note = linkedNote else { return }
        workspace.run(NoteUnlinkSession(course: courseId, note: note.id, session: sessionId))
    }

    /// The linked note gives way now; the new one is made on saving, after the units, so they name it.
    func makeNewNote() {
        unlinkNote()
        makesNote = !hasNote
    }

    // MARK: Attendance

    var takesAttendance: Bool { workspace.can(AttendanceSet(course: courseId, session: sessionId, state: .absent)) }

    // MARK: Announcements

    /// An assignment the quick-add line put in, listed above it to show it went in.
    func announce(_ parsed: QuickAdd) {
        let due = parsed.due.map { " · " + $0.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)) } ?? ""
        announced.append(parsed.title + due)
    }

    func addExam() {
        let c = workspace.calendar
        let start = c.date(byAdding: .hour, value: 24 + 9, to: c.startOfDay(for: workspace.now)) ?? workspace.now
        addingExam = Exam(device: workspace.device, at: .now, title: "", start: start)
    }

    /// The exam editor saves on its own; a title in the file afterwards means it went in.
    func examClosed(_ exam: Exam) {
        if let saved = file?.exams.first(where: { $0.id == exam.id }) { announced.append(saved.title) }
    }

    // MARK: Saving

    /// No rows without lecture files: progress isn't shown then, and a file the class links whole would otherwise
    /// block saving from out of sight.
    private var keptRows: [Row] { items.contains(.progress) ? rows.filter(\.included) : [] }

    /// Only the ranges the class doesn't have already: every row starts on the class's own pages.
    var ranges: [SessionMaterial] {
        let kept = keptRows.map { SessionMaterial(materialId: $0.id, firstPage: $0.first, lastPage: $0.last) }
        return session?.changedRanges(kept) ?? kept
    }

    var action: SessionWrapUp {
        SessionWrapUp(course: courseId, session: sessionId, ranges: ranges, units: units, attendance: attendance)
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

    /// Only what the form itself can't show (2026-11-08): a row lacking an end already reads so on its bar, with
    /// 저장 off, so the sheet adds no sentence for it.
    var note: String? {
        keptRows.contains { $0.first == nil || $0.last == nil } ? nil : workspace.refusal(action)
    }

    /// False when the save failed, so a run through several classes stays on this one.
    @discardableResult func wrapUp() -> Bool {
        guard workspace.run(action) != nil else { return false }
        // After the units are saved, so the note is named by the class's day and units like any class note.
        if makesNote && !hasNote { _ = workspace.note(.rough, of: sessionId, in: courseId) }
        return true
    }
}

extension WrapUpItem {
    var label: String {
        switch self {
        case .progress: String(localized: .wrapUpProgress)
        case .units: String(localized: .wrapUpUnits)
        case .note: String(localized: .wrapUpNote)
        case .attendance: String(localized: .wrapUpAttendance)
        }
    }
}
