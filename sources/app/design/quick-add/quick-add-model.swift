import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class QuickAddModel {
    let workspace: Workspace
    let fixedCourse: UUID?
    let defaultCourse: UUID?
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

    private(set) var read: QuickAdd

    private var reader: QuickAdd.Reader { Self.reader(workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse) }

    private static func reader(_ workspace: Workspace, fixedCourse: UUID?, defaultCourse: UUID?) -> QuickAdd.Reader {
        QuickAdd.Reader(
            courses: workspace.currentCourses.map(\.file.course), codes: workspace.catalog.codes, fixedCourse: fixedCourse,
            defaultCourse: defaultCourse, now: workspace.now, calendar: workspace.calendar)
    }

    var parsed: QuickAdd? { isEmpty ? nil : read }

    func canAdd(_ parsed: QuickAdd) -> Bool { parsed.courseId != nil && !parsed.title.isEmpty }

    func courseTitle(_ id: UUID) -> String? { workspace.course(id)?.title }

    func accent(_ id: UUID) -> CourseAccent { workspace.accent(id) }

    func due(_ parsed: QuickAdd) -> String? {
        parsed.due.map { CourseFile.deadline($0, calendar: workspace.calendar, locale: locale) }
    }

    enum Chip: Hashable {
        case course(UUID?)
        case due(Date?)
        case repeats(AssignmentRepeat?)
        case folder(String?)

        // 행에서 칩의 identity는 값이 아니라 종류다. 값을 키로 쓰면 날짜를 고를 때 마감 칩이 새 뷰가 되어, 고르는 도중에
        // 자기 popover가 닫혔다.
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

    func isDimmed(_ chip: Chip) -> Bool {
        switch chip {
        case let .course(id): id == nil && isEmpty
        case let .due(date): date == nil && showsEmptyChips
        case let .repeats(repeats): repeats == nil
        case let .folder(name): name == nil
        }
    }

    var courses: [(id: UUID, title: String)] { workspace.currentCourses.map { ($0.id, $0.title) } }

    private func set(_ value: QuickAdd.Value) { text = reader.line(text, setting: value) }

    func pickCourse(_ id: UUID) { set(.course(id)) }

    func pickDue(_ date: Date?) { set(.due(date)) }

    func pickRepeats(_ repeats: AssignmentRepeat?) { set(.repeats(repeats)) }

    var dueWeekday: Int? { parsed?.due.map { workspace.calendar.isoWeekday(of: $0) } }

    var newDue: Date {
        let c = workspace.calendar
        return c.date(byAdding: .minute, value: QuickAdd.defaultMinute, to: c.startOfDay(for: workspace.now)) ?? workspace.now
    }

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

    func renumber(kind: AssignmentKind, number: Int) { set(.kind(kind, number)) }

    func submit() {
        if let parsed, canAdd(parsed) { add(parsed) }
    }

    @discardableResult
    func add(_ parsed: QuickAdd) -> Bool {
        guard let id = parsed.courseId, !parsed.title.isEmpty,
            workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil
        else { return false }
        text = ""
        return true
    }
}
