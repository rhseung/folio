import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class AssignmentsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var editing: Assignment?
    var pending: PendingAction?

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    // 저장한 변경이 페이지에 과목을 다시 넘기지 않아도 보이도록 매번 찾는다.
    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    var subtitle: String {
        let all = course.file.assignments
        let open = all.filter(\.status.isOpen)
        let undated = open.filter { $0.due == nil }.count
        return
            ([String(localized: .assignmentsCount(all.count))]
            + (open.isEmpty ? [] : [String(localized: .assignmentsOpenCount(open.count))])
            + (undated == 0 ? [] : [String(localized: .assignmentsUndatedCount(undated))])).joined(separator: " · ")
    }

    func groups(now: Date) -> [(group: AssignmentGroup, items: [Assignment])] {
        let grouped = Dictionary(grouping: course.file.assignments) { AssignmentGroup($0, now: now) }
        return AssignmentGroup.allCases.compactMap { g in grouped[g].map { (g, g.sorted($0)) } }
    }

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
        var score: String?
        var component: String?
        var suggestsSubmitted: Bool
    }

    func row(_ a: Assignment) -> Row {
        let file = course.file
        let files = AssignmentFiles.materials(of: a, in: file.materials)
        let submissions = files.filter {
            ($0.kind ?? AssignmentFiles.guessKind(fileName: ($0.path as NSString).lastPathComponent)) == .submission
        }.count
        let scores = file.scores.filter { $0.assignmentId == a.id }
        return Row(
            files: files, problems: files.count - submissions, submissions: submissions,
            score: scores.isEmpty ? nil : "\(scores.map(\.score).reduce(0, +).formatted())/\(scores.map(\.max).reduce(0, +).formatted())",
            component: a.componentGroup ?? file.components.first { $0.id == a.componentId }?.name,
            suggestsSubmitted: AssignmentFiles.suggestsSubmitted(a, files: files))
    }

    func due(_ a: Assignment) -> (date: String, time: String?) {
        guard let due = a.due else { return (String(localized: .assignmentsNoDue), nil) }
        let c = workspace.calendar
        return (
            due.formatted(.dateTime.month().day()),
            due.formatted(.dateTime.weekday()) + " " + TimeMenu.label(c.component(.hour, from: due) * 60 + c.component(.minute, from: due))
        )
    }

    func dueChip(_ a: Assignment, now: Date) -> (text: String, tone: Tone)? {
        guard a.status.isOpen, let due = a.due else { return nil }
        let tone: Tone =
            switch DueUrgency(due: due, now: now, settings: workspace.settings, calendar: workspace.calendar) {
            case .urgent: .danger
            case .soon: .warning
            case .later: .plain
            }
        switch DueState(due: due, now: now, calendar: workspace.calendar) {
        case .none: return nil
        case .overdue(let d): return (String(localized: d == 0 ? .assignmentsJustOverdue : .assignmentsOverdueDays(d)), .danger)
        case .hours(let h): return (String(localized: .assignmentsHoursLeft(h)), tone)
        case .days(let d): return ("D-\(d)", tone)
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
