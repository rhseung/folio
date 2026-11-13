import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class QuickAddModel {
    let workspace: Workspace
    let fixedCourse: UUID?
    /// The course the window shows when the line was opened; a course typed into the line wins over it.
    let defaultCourse: UUID?
    /// Every chip from the start, the ones with nothing read yet dimmed, so the line shows what it can read (Today and
    /// the toolbar's popover, 2026-11-09 user). The assignments screen shows only what was read.
    let showsEmptyChips: Bool
    var text = "" {
        didSet { read = reader.read(text) }
    }
    var locale = Locale.autoupdatingCurrent

    init(workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil, showsEmptyChips: Bool = false) {
        self.workspace = workspace
        self.fixedCourse = fixedCourse
        let defaultCourse = fixedCourse == nil ? defaultCourse.flatMap { workspace.course($0)?.id } : nil
        self.defaultCourse = defaultCourse
        self.showsEmptyChips = showsEmptyChips
        read = Self.reader(workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse).read("")
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the line reads. Read once per edit and kept: the chips, the pills and each chip all ask for it in one
    /// pass, and every read runs the date detector.
    private(set) var read: QuickAdd

    private var reader: QuickAdd.Reader { Self.reader(workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse) }

    private static func reader(_ workspace: Workspace, fixedCourse: UUID?, defaultCourse: UUID?) -> QuickAdd.Reader {
        QuickAdd.Reader(
            courses: workspace.currentCourses.map(\.file.course), codes: workspace.catalog.codes, fixedCourse: fixedCourse,
            defaultCourse: defaultCourse, now: workspace.now, calendar: workspace.calendar)
    }

    /// What will be saved. Only the line: a chip's pick is written into it, so the two never disagree.
    var parsed: QuickAdd? { isEmpty ? nil : read }

    func canAdd(_ parsed: QuickAdd) -> Bool { parsed.courseId != nil && !parsed.title.isEmpty }

    func courseTitle(_ id: UUID) -> String? { workspace.course(id)?.title }

    func accent(_ id: UUID) -> CourseAccent { workspace.accent(id) }

    func due(_ parsed: QuickAdd) -> String? {
        parsed.due.map { CourseFile.deadline($0, calendar: workspace.calendar, locale: locale) }
    }

    /// The chips under the line, always in this order so none moves as others come and go: course, deadline, repeat,
    /// folder. The course chip is left out where the field belongs to a course. With `showsEmptyChips` all four stand
    /// from the start, dimmed until the line reads them; otherwise the deadline chip stays even without one, so a
    /// deadline can be added by touch, and the repeat and folder chips show only when the line has them.
    enum Chip: Hashable {
        case course(UUID?)
        case due(Date?)
        case repeats(AssignmentRepeat?)
        case folder(String?)

        /// A chip's identity in the row: its kind, not its value. Keyed by value, picking a date made the deadline
        /// chip a new view, which closed its own popover mid-pick.
        enum Kind { case course, due, repeats, folder }

        var kind: Kind {
            switch self {
            case .course: .course
            case .due: .due
            case .repeats: .repeats
            case .folder: .folder
            }
        }
    }

    var chips: [Chip] {
        let shown = parsed ?? (defaultCourse != nil || showsEmptyChips ? read : nil)
        guard let shown else { return [] }
        var chips: [Chip] = []
        if fixedCourse == nil { chips.append(.course(shown.courseId)) }
        if showsEmptyChips {
            return chips + [.due(shown.due), .repeats(shown.repeats), .folder(shown.folderName)]
        }
        if !isEmpty {
            chips.append(.due(shown.due))
            if let repeats = shown.repeats { chips.append(.repeats(repeats)) }
            if let folder = shown.folderName { chips.append(.folder(folder)) }
        }
        return chips
    }

    /// A chip with nothing read, before anything is typed: a placeholder rather than the warning a typed line
    /// without a course gets.
    func isDimmed(_ chip: Chip) -> Bool {
        switch chip {
        case let .course(id): id == nil && isEmpty
        case let .due(date): date == nil && showsEmptyChips
        case let .repeats(repeats): repeats == nil
        case let .folder(name): name == nil
        }
    }

    var courses: [(id: UUID, title: String)] { workspace.currentCourses.map { ($0.id, $0.title) } }

    /// Each pick rewrites the line (`QuickAdd.Reader.line`), and the chips follow what it then reads.
    private func set(_ value: QuickAdd.Value) { text = reader.line(text, setting: value) }

    func pickCourse(_ id: UUID) { set(.course(id)) }

    /// Clearing the deadline takes the repeat with it, as `매주` and the like are among the deadline's words.
    func pickDue(_ date: Date?) { set(.due(date)) }

    func pickRepeats(_ repeats: AssignmentRepeat?) { set(.repeats(repeats)) }

    /// The weekday a weekly rule without weekdays falls on: the deadline's.
    var dueWeekday: Int? { parsed?.due.map { workspace.calendar.isoWeekday(of: $0) } }

    /// Where an empty deadline chip starts its calendar: today at the default deadline minute.
    var newDue: Date {
        let c = workspace.calendar
        return c.date(byAdding: .minute, value: QuickAdd.defaultMinute, to: c.startOfDay(for: workspace.now)) ?? workspace.now
    }

    /// `D-3`, or the hours left on the day itself, as the assignments list counts.
    func left(_ due: Date) -> (text: String, overdue: Bool)? {
        switch DueState(due: due, now: workspace.now, calendar: workspace.calendar) {
        case .none: nil
        case .overdue(let d): (String(localized: d == 0 ? .assignmentsJustOverdue : .assignmentsOverdueDays(d)), true)
        case .hours(let h): (String(localized: .assignmentsHoursLeft(h)), false)
        case .days(let d): ("D-\(d)", false)
        }
    }

    var kind: (kind: AssignmentKind, number: Int)? {
        let r = read
        return r.kind.flatMap { k in r.number.map { (k, $0) } }
    }

    /// The number chip rewrites the line's `HW5`, or adds one: the folder is named from the title, which is what is
    /// typed.
    func renumber(kind: AssignmentKind, number: Int) { set(.kind(kind, number)) }

    /// Return is the only way to add: the field holds the line and nothing else (2026-11-08 user). An empty line, or
    /// one without a course or title, does nothing; the chips below already say what is missing.
    func submit() {
        if let parsed, canAdd(parsed) { add(parsed) }
    }

    /// Whether it went in; the line clears only then.
    @discardableResult
    func add(_ parsed: QuickAdd) -> Bool {
        guard let id = parsed.courseId, !parsed.title.isEmpty,
            workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil
        else { return false }
        text = ""
        return true
    }
}
