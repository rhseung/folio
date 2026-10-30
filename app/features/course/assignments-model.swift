import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class AssignmentsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var editing: Assignment?
    var removing: Assignment?

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    /// Looked up each time, so a saved change shows without the page being handed the course again.
    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    var subtitle: String {
        let all = course.file.assignments
        let open = all.filter(\.status.isOpen)
        let undated = open.filter { $0.due == nil }.count
        return ([String(localized: .assignmentsCount(all.count))] + (open.isEmpty ? [] : [String(localized: .assignmentsOpenCount(open.count))])
                + (undated == 0 ? [] : [String(localized: .assignmentsUndatedCount(undated))])).joined(separator: " · ")
    }

    func groups(now: Date) -> [(group: AssignmentGroup, items: [Assignment])] {
        let grouped = Dictionary(grouping: course.file.assignments) { AssignmentGroup($0, now: now) }
        return AssignmentGroup.allCases.compactMap { g in grouped[g].map { (g, g.sorted($0)) } }
    }

    func remove(_ a: Assignment) { workspace.run(AssignmentRemove(course: course.id, assignment: a.id)) }

    func setStatus(_ a: Assignment, _ status: AssignmentStatus) {
        workspace.run(AssignmentStatusSet(course: course.id, assignment: a.id, status: status))
    }

    func drop(_ urls: [URL], on a: Assignment) {
        workspace.importFiles(urls, into: AssignmentFiles.path(of: a), course: course.id)
    }

    struct Row {
        var files: [FolioDomain.Material]
        var problems: Int
        var submissions: Int
        /// A group-scored assignment has one entry per component; the row shows their total.
        var score: String?
        var component: String?
        var suggestsSubmitted: Bool
    }

    func row(_ a: Assignment) -> Row {
        let file = course.file
        let files = AssignmentFiles.materials(of: a, in: file.materials)
        let submissions = files.filter { ($0.kind ?? AssignmentFiles.guessKind(fileName: ($0.path as NSString).lastPathComponent)) == .submission }.count
        let scores = file.scores.filter { $0.assignmentId == a.id }
        return Row(files: files, problems: files.count - submissions, submissions: submissions,
                   score: scores.isEmpty ? nil : "\(scores.map(\.score).reduce(0, +).formatted())/\(scores.map(\.max).reduce(0, +).formatted())",
                   component: a.componentGroup ?? file.components.first { $0.id == a.componentId }?.name,
                   suggestsSubmitted: AssignmentFiles.suggestsSubmitted(a, files: files))
    }

    func due(_ a: Assignment) -> (date: String, time: String?) {
        guard let due = a.due else { return (String(localized: .assignmentsNoDue), nil) }
        let c = workspace.calendar
        return (due.formatted(.dateTime.month().day()), due.formatted(.dateTime.weekday()) + " " + TimeMenu.label(c.component(.hour, from: due) * 60 + c.component(.minute, from: due)))
    }

    func dueChip(_ a: Assignment, now: Date) -> (text: String, tone: Tone)? {
        guard a.status.isOpen else { return nil }
        switch DueState(due: a.due, now: now, calendar: workspace.calendar) {
        case .none: return nil
        case .overdue(let d): return (String(localized: d == 0 ? .assignmentsJustOverdue : .assignmentsOverdueDays(d)), .danger)
        case .hours(let h): return (String(localized: .assignmentsHoursLeft(h)), .danger)
        case .days(let d): return ("D-\(d)", d <= 3 ? .warning : .plain)
        }
    }
}

extension AssignmentGroup {
    var label: String {
        switch self {
        case .overdue: String(localized: .assignmentsGroupOverdue)
        case .open: String(localized: .assignmentsGroupOpen)
        case .submitted: String(localized: .assignmentsGroupSubmitted)
        case .graded: String(localized: .assignmentsGroupGraded)
        }
    }
}

enum ScoreTarget: Hashable {
    case none, component(UUID), group(String)
}

/// Edits one assignment on a draft; nothing is saved until confirmed.
@MainActor @Observable
final class AssignmentSheetModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let assignment: Assignment
    var title = ""
    var hasDue = false
    var due = Date.now
    var status: AssignmentStatus = .todo
    var repeats: AssignmentRepeat?
    private(set) var target = ScoreTarget.none
    /// Typed score and max per component, so switching the target keeps what was typed.
    var scores: [UUID: String] = [:]
    var maxes: [UUID: String] = [:]
    var memo = ""

    init(workspace: Workspace, course: LoadedCourse, assignment: Assignment) {
        self.workspace = workspace
        initial = course
        self.assignment = assignment
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var files: [FolioDomain.Material] { AssignmentFiles.materials(of: assignment, in: course.file.materials) }
    var folder: String { AssignmentFiles.path(of: assignment) }
    var sheetTitle: String { String(localized: .commonEditNamed(assignment.title)) }

    var invalid: Bool {
        targetComponents.contains { c in !(scores[c.id] ?? "").isEmpty && (Double(scores[c.id] ?? "") == nil || (Double(maxes[c.id] ?? "") ?? 0) <= 0) }
    }

    /// The files are found by the folder the title names, so a title naming another folder loses them here.
    var titleDetail: String? {
        let renamed = AssignmentFiles.path(of: Assignment(device: workspace.device, at: .now, title: title))
        return renamed == folder || files.isEmpty ? nil : String(localized: .assignmentsRenamedFolder(renamed))
    }

    var repeatDetail: String? {
        repeats != .weekly ? nil : String(localized: hasDue ? .assignmentsRepeatNext : .assignmentsRepeatNeedsDue)
    }

    var sortedComponents: [GradeComponent] { course.file.components.sorted { $0.order < $1.order } }

    var targetComponents: [GradeComponent] {
        switch target {
        case .none: []
        case .component(let id): sortedComponents.filter { $0.id == id }
        case .group(let g): sortedComponents.filter { $0.group == g }
        }
    }

    // A group heads its components, indented under it, so picking the whole group or one part reads as a tree.
    var targetOptions: [PickOption<ScoreTarget>] {
        var options = [PickOption(id: ScoreTarget.none, title: String(localized: .assignmentsNoTarget))]
        var seen = Set<String>()
        for c in sortedComponents {
            guard let g = c.group else { options.append(PickOption(id: .component(c.id), title: c.name)); continue }
            guard seen.insert(g).inserted else { continue }
            let members = sortedComponents.filter { $0.group == g }
            options.append(PickOption(id: .group(g), title: String(localized: .assignmentsWholeGroup(g)),
                                      detail: String(localized: .assignmentsWholeGroupDetail(members.count))))
            options += members.map { PickOption(id: .component($0.id), title: $0.name, depth: 1) }
        }
        return options
    }

    /// A component without a typed max takes the one its last score had, as a weekly report is out of the same points.
    func pick(_ t: ScoreTarget) {
        target = t
        for c in targetComponents where (maxes[c.id] ?? "").isEmpty {
            maxes[c.id] = course.file.scores.last { $0.componentId == c.id }?.max.formatted()
        }
    }

    func load() {
        title = assignment.title
        hasDue = assignment.due != nil
        due = assignment.due ?? workspace.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: workspace.now) ?? workspace.now
        status = assignment.status
        repeats = assignment.repeats
        memo = assignment.memo
        let own = course.file.scores.filter { $0.assignmentId == assignment.id }
        for s in own {
            scores[s.componentId] = s.score.formatted()
            maxes[s.componentId] = s.max.formatted()
        }
        target = assignment.componentGroup.map { .group($0) } ?? (assignment.componentId ?? own.first?.componentId).map { .component($0) } ?? .none
    }

    func importFiles(_ urls: [URL]) { workspace.importFiles(urls, into: folder, course: course.id) }

    func apply() -> Bool {
        let scored = targetComponents
        let entered = scored.compactMap { c -> AssignmentSave.Score? in
            guard let s = Double(scores[c.id] ?? ""), let m = Double(maxes[c.id] ?? ""), m > 0 else { return nil }
            return AssignmentSave.Score(component: c.id, score: s, max: m)
        }
        var componentId: UUID?, group: String?
        if case .component(let id) = target { componentId = id }
        if case .group(let g) = target { group = g }
        return workspace.run(AssignmentSave(course: course.id, assignment: assignment.id, title: title, due: hasDue ? due : nil, status: status,
                                            repeats: repeats, componentId: componentId, componentGroup: group, memo: memo,
                                            components: scored.map(\.id), scores: entered)) != nil
    }

    func delete() { workspace.run(AssignmentRemove(course: course.id, assignment: assignment.id)) }
}
