import FolioActions
import FolioDomain
import Foundation
import Observation

/// One class's wrap-up, asked when its recording stops, from the today screen, and from the class's menu. What the class
/// has nothing for (`CourseFile.wrapUpGaps`) opens for input; the rest folds into one line each to confirm. Saving writes
/// everything in one action.
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
    private let initial: (units: [UUID], topic: String, attendance: AttendanceState)

    /// The items shown open, in asking order: what was missing when the sheet opened, and any reopened from its line.
    private(set) var open: [WrapUpItem]
    var units: [UUID]
    var topic: String
    var attendance: AttendanceState
    /// The class's rough note is made on saving, after the topic is, so the note is named after it.
    var makesNote = false
    var newUnit = ""
    /// Assignments added from the announcements line, to show they went in.
    private(set) var announced: [String] = []
    var assignmentText = ""
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
        open = file.flatMap { f in s.map { f.wrapUpGaps(of: $0, recorded: recorded) } } ?? []
        // From locals: the observed properties can't be read back before every stored property is set.
        let initial = (units: s?.unitIds ?? [], topic: s?.topic ?? "",
                       attendance: file?.attendance.first { $0.sessionId == session }?.state ?? AttendanceState.present)
        units = initial.units
        topic = initial.topic
        attendance = initial.attendance
        self.initial = initial
        suggest()
    }

    var changed: Bool {
        edited || makesNote || units != initial.units || topic != initial.topic || attendance != initial.attendance
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

    /// Every item this class can be asked about, in asking order: progress only for a course with lecture files.
    var items: [WrapUpItem] {
        WrapUpItem.allCases.filter { $0 != .progress || !(file?.lectureFiles.isEmpty ?? true) }
    }

    var openItems: [WrapUpItem] { items.filter(isOpen) }

    var folded: [WrapUpItem] { items.filter { !open.contains($0) } }
    func isOpen(_ item: WrapUpItem) -> Bool { open.contains(item) }

    func reopen(_ item: WrapUpItem) {
        guard !open.contains(item) else { return }
        open = items.filter { open.contains($0) || $0 == item }
    }

    func label(_ item: WrapUpItem) -> String { item.label }

    /// A folded item's line: what the class already has.
    func summary(_ item: WrapUpItem) -> String {
        guard let file, let session else { return "" }
        switch item {
        case .progress:
            return session.materials.compactMap { link in
                guard let pages = link.pages, let m = file.materials.first(where: { $0.id == link.materialId }), m.role == .lecture else { return nil }
                return String(localized: .wrapUpProgressLine((m.path as NSString).lastPathComponent, pages.lowerBound, pages.upperBound))
            }.joined(separator: ", ")
        case .units: return unitTitles(units)
        case .topic: return topic
        case .note:
            let id = session.roughNoteId ?? session.reviewNoteId
            return id.flatMap { id in file.notes.first { $0.id == id } }.map { (($0.path as NSString).lastPathComponent as NSString).deletingPathExtension } ?? ""
        case .attendance:
            let state = AttendanceState.steps.first { $0.value == attendance }?.label ?? ""
            return recorded || file.recordings.contains(where: { $0.sessionId == sessionId })
                ? String(localized: .wrapUpAttendanceRecorded(state)) : state
        }
    }

    // MARK: Progress

    private func suggest() {
        guard let file, let session else { return }
        rows = file.suggestedProgress(for: session, viewed: viewed, pageCounts: pageCounts)
            .map { Row(id: $0.materialId, first: $0.firstPage, last: $0.lastPage) }
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

    /// Where the numbers came from, under the file's name: what the last class reached, what the recording saw,
    /// and how long the file is.
    func detail(_ id: UUID) -> String {
        guard let file, let session else { return "" }
        var parts: [String] = []
        if let resume = file.resumePage(of: id, for: session) { parts.append(String(localized: .sessionsProgressLastClass(resume - 1))) }
        if let seen = viewed.first(where: { $0.materialId == id }), let pages = seen.pages {
            parts.append(String(localized: .sessionsProgressRecorded(pages.lowerBound, pages.upperBound)))
        }
        if let count = pageCounts[id] { parts.append(String(localized: .sessionsProgressPageCount(count))) }
        return parts.joined(separator: " · ")
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

    func reads(_ id: UUID) -> (ClosedRange<Int>) -> String? {
        let file = file
        return { file?.sectionLabel(of: id, pages: $0) }
    }

    func seen(_ id: UUID) -> ClosedRange<Int>? { viewed.first { $0.materialId == id }?.pages }

    func resume(_ id: UUID) -> Int? {
        guard let file, let session else { return nil }
        return file.resumePage(of: id, for: session)
    }

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

    /// The course's units in outline order, the last class's first: a class most often carries on with them. Listed
    /// first only; none is chosen for the user.
    var unitOptions: [PickOption<UUID>] {
        guard let file else { return [] }
        return UnitTree.outline(file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }

    var recentUnits: [FolioDomain.Unit] {
        guard let file, let session else { return [] }
        return file.recentUnits(before: session).compactMap { id in file.units.first { $0.id == id } }.filter { !units.contains($0.id) }
    }

    func unitTitles(_ ids: [UUID]) -> String {
        guard let file else { return "" }
        return UnitTree.deepest(ids.compactMap { id in file.units.first { $0.id == id } }, in: file.units).map(\.title).joined(separator: " · ")
    }

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

    var hasNote: Bool { session.map { $0.roughNoteId != nil || $0.reviewNoteId != nil } ?? false }

    /// Notes no class points at yet, the ones that could be this class's.
    var unlinkedNotes: [NoteEntry] {
        guard let file else { return [] }
        let taken = Set(file.sessions.flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        return file.notes.filter { !taken.contains($0.id) && $0.kind != .review && $0.examId == nil }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func noteName(_ note: NoteEntry) -> String { ((note.path as NSString).lastPathComponent as NSString).deletingPathExtension }

    func linkNote(_ id: UUID) {
        workspace.run(NoteLink(course: courseId, note: id, kind: .rough, session: sessionId, exam: nil, units: [], math: nil))
        makesNote = false
    }

    // MARK: Attendance

    var takesAttendance: Bool { workspace.can(AttendanceSet(course: courseId, session: sessionId, state: .absent)) }

    // MARK: Announcements

    var parsedAssignment: QuickAdd? {
        let text = assignmentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let file else { return nil }
        return QuickAdd.parse(text, courses: [file.course], codes: workspace.catalog.codes, fixedCourse: courseId,
                              now: workspace.now, calendar: workspace.calendar)
    }

    func addAssignment() {
        guard let parsed = parsedAssignment, !parsed.title.isEmpty,
              workspace.run(AssignmentAdd(course: courseId, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil else { return }
        let due = parsed.due.map { " · " + $0.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)) } ?? ""
        announced.append(parsed.title + due)
        assignmentText = ""
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

    /// The rows only while progress is open. Folded, they aren't on screen, and the class's links stay as they are,
    /// as the command leaves what it isn't given: a file linked whole would otherwise block saving from out of sight.
    private var keptRows: [Row] { isOpen(.progress) ? rows.filter(\.included) : [] }

    var action: SessionWrapUp {
        SessionWrapUp(course: courseId, session: sessionId,
                      ranges: keptRows.map { SessionMaterial(materialId: $0.id, firstPage: $0.first, lastPage: $0.last) },
                      units: units, topic: topic, attendance: attendance)
    }

    /// Why saving is off: a kept file without both pages says nothing about how far the class went.
    var refusal: String? {
        if let row = keptRows.first(where: { $0.first == nil || $0.last == nil }) {
            return String(localized: .sessionsProgressMissingPages(name(row.id)))
        }
        return workspace.refusal(action)
    }

    var note: String? {
        refusal ?? (viewed.isEmpty || !isOpen(.progress) ? nil : String(localized: .sessionsProgressFromRecording))
    }

    /// False when the save failed, so a run through several classes stays on this one.
    @discardableResult func wrapUp() -> Bool {
        guard workspace.run(action) != nil else { return false }
        // After the topic is saved, so the note is named by the class's day and topic like any class note.
        if makesNote && !hasNote { _ = workspace.note(.rough, of: sessionId, in: courseId) }
        return true
    }
}

extension WrapUpItem {
    var label: String {
        switch self {
        case .progress: String(localized: .wrapUpProgress)
        case .units: String(localized: .wrapUpUnits)
        case .topic: String(localized: .wrapUpTopic)
        case .note: String(localized: .wrapUpNote)
        case .attendance: String(localized: .wrapUpAttendance)
        }
    }
}
