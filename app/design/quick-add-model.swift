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
    var text = "" {
        didSet {
            read = Self.reading(text, workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse)
            picks.keep(over: read)
        }
    }
    private(set) var picks = QuickAddPicks()
    var locale = Locale.autoupdatingCurrent

    init(workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil) {
        self.workspace = workspace
        self.fixedCourse = fixedCourse
        let defaultCourse = fixedCourse == nil ? defaultCourse.flatMap { workspace.course($0)?.id } : nil
        self.defaultCourse = defaultCourse
        read = Self.reading("", workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse)
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the line reads, before the chips' picks. Read once per edit and kept: the chips, the pills and each chip
    /// all ask for it in one pass, and every read runs the date detector.
    private(set) var read: QuickAdd

    private static func reading(_ text: String, workspace: Workspace, fixedCourse: UUID?, defaultCourse: UUID?) -> QuickAdd {
        QuickAdd.parse(text, courses: workspace.currentCourses.map(\.file.course), codes: workspace.catalog.codes, fixedCourse: fixedCourse,
                       defaultCourse: defaultCourse, now: workspace.now, calendar: workspace.calendar)
    }

    /// What will be saved: the line as read, with what was picked on its chips.
    var parsed: QuickAdd? { isEmpty ? nil : picks.applied(to: read) }

    func canAdd(_ parsed: QuickAdd) -> Bool { parsed.courseId != nil && !parsed.title.isEmpty }

    func courseTitle(_ id: UUID) -> String? { workspace.course(id)?.title }

    func accent(_ id: UUID) -> CourseAccent { workspace.accent(id) }

    func due(_ parsed: QuickAdd) -> String? {
        parsed.due.map { CourseFile.deadline($0, calendar: workspace.calendar, locale: locale) }
    }

    /// The chips under the line, always in this order so none moves as others come and go: course, deadline, repeat,
    /// folder. The course chip is left out where the field belongs to a course; the deadline chip stays even without
    /// one, so a deadline can be added by touch; the repeat and folder chips show only when the line has them.
    enum Chip: Hashable {
        case course(UUID?)
        case due(Date?)
        case weekly
        case folder(String)

        /// A chip's identity in the row: its kind, not its value. Keyed by value, picking a date made the deadline
        /// chip a new view, which closed its own popover mid-pick.
        enum Kind { case course, due, weekly, folder }

        var kind: Kind {
            switch self {
            case .course: .course
            case .due: .due
            case .weekly: .weekly
            case .folder: .folder
            }
        }
    }

    var chips: [Chip] {
        let shown = parsed ?? (defaultCourse != nil ? read : nil)
        guard let shown else { return [] }
        var chips: [Chip] = []
        if fixedCourse == nil { chips.append(.course(shown.courseId)) }
        if !isEmpty {
            chips.append(.due(shown.due))
            if shown.repeats == .weekly { chips.append(.weekly) }
            if let folder = shown.folderName { chips.append(.folder(folder)) }
        }
        return chips
    }

    var courses: [(id: UUID, title: String)] { workspace.currentCourses.map { ($0.id, $0.title) } }

    func pickCourse(_ id: UUID) { picks.pickCourse(id, over: read) }

    func pickDue(_ date: Date?) {
        picks.pickDue(date, over: read)
        if date == nil, parsed?.repeats != nil { picks.pickRepeats(nil, over: read) }
    }

    func pickRepeats(_ repeats: AssignmentRepeat?) { picks.pickRepeats(repeats, over: read) }

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

    /// The number chip rewrites the line's `HW5`: the folder is named from the title, which is what is typed.
    func renumber(kind: AssignmentKind, number: Int) {
        guard let range = read.kindRange else { return }
        text = QuickAdd.renumbered(text, at: range, kind: kind, number: number)
    }

    /// Return is the only way to add: the field holds the line and nothing else (2026-11-08 user). An empty line, or
    /// one without a course or title, does nothing; the chips below already say what is missing.
    func submit() {
        if let parsed, canAdd(parsed) { add(parsed) }
    }

    /// Whether it went in; the line clears only then.
    @discardableResult
    func add(_ parsed: QuickAdd) -> Bool {
        guard let id = parsed.courseId, !parsed.title.isEmpty,
              workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil else { return false }
        text = ""
        picks = QuickAddPicks()
        return true
    }
}
