import FolioActions
import FolioCore
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
        workspace.importFiles(urls, into: AssignmentFiles.path(of: a, kinds: workspace.settings.assignmentKindTable), course: course.id)
    }

    struct Row {
        var files: [FolioDomain.Material]
        var problems: Int
        var submissions: Int
        var score: String?
        var component: String?
        var lms: Bool
        var submittedOn: String?
        var lateSubmitted: Bool
    }

    func row(_ a: Assignment) -> Row {
        let file = course.file
        let files = AssignmentFiles.materials(of: a, in: file.materials, kinds: workspace.settings.assignmentKindTable)
        let submissions = files.filter {
            ($0.kind
                ?? AssignmentFiles.guessKind(
                    fileName: ($0.path as NSString).lastPathComponent, kinds: workspace.settings.assignmentKindTable)) == .submission
        }.count
        let scores = file.scores.filter { $0.assignmentId == a.id }
        return Row(
            files: files, problems: files.count - submissions, submissions: submissions,
            score: scores.isEmpty ? nil : "\(scores.map(\.score).reduce(0, +).formatted())/\(scores.map(\.max).reduce(0, +).formatted())",
            component: a.componentGroup ?? file.components.first { $0.id == a.componentId }?.name,
            lms: a.lmsId != nil,
            submittedOn: a.status.isOpen
                ? nil
                : a.submittedAt.map { String(localized: .assignmentsSubmittedOn(CourseFile.deadline($0, calendar: workspace.calendar))) },
            lateSubmitted: !a.status.isOpen && file.lateness(of: a, at: workspace.now) != nil)
    }

    // 마감은 공부일로 센 상대 날짜와 시각으로 보인다. 하루 안이면 시간, 한 시간 안이면 분, 7일부터는 주, 30일부터는 달로 센다. 급한 정도는 상대 날짜의 색으로만 보이고 칩은 두지 않는다.
    struct Due {
        var date: String
        var time: String?
        var tone: Tone
    }

    func due(_ a: Assignment, now: Date) -> Due {
        guard let due = a.due else { return Due(date: String(localized: .assignmentsNoDue), tone: .plain) }
        let c = workspace.calendar
        let settings = workspace.settings
        let days = RelativeDate.days(due, from: now, settings: settings, calendar: c)
        let tone: Tone =
            if !a.status.isOpen {
                .plain
            } else if due < now {
                .danger
            } else {
                switch DueUrgency(due: due, now: now, settings: settings, calendar: c) {
                case .urgent: .danger
                case .soon: .warning
                case .later: .plain
                }
            }
        let date = RelativeDate.distance(due, from: now, settings: settings, calendar: c)
        let day = RelativeDate.day(due, from: now, settings: settings, calendar: c, short: true)
        // 종일 마감은 시각이 없어서 위 줄이 이미 "오늘", "내일"이면 아래 줄을 비운다.
        guard RelativeDate.hasTime(due, calendar: c) else { return Due(date: date, time: abs(days) <= 1 ? nil : day, tone: tone) }
        let time = RelativeDate.time(due, calendar: c)
        // 하루 안이면 위 줄이 남은 시간이므로, 아래 줄에 어느 날의 몇 시인지 둔다.
        if RelativeDate.within(due, from: now) != nil { return Due(date: date, time: day + " " + time, tone: tone) }
        // 날짜와 시각을 함께 쓰면 좁은 폭에서 날짜 칸을 넘어 꺾이므로, 시각은 일주일 안으로 들어올 때부터 보인다.
        let when =
            switch abs(days) {
            case ...1: time
            case ..<RelativeDate.week: day + " " + time
            default: day
            }
        return Due(date: date, time: when, tone: tone)
    }
}

extension AssignmentGroup {
    var label: String {
        switch self {
        case .overdue: String(localized: .assignmentsGroupOverdue)
        case .open: String(localized: .assignmentsGroupOpen)
        case .submitted: String(localized: .assignmentsGroupSubmitted)
        case .graded: String(localized: .assignmentsGroupGraded)
        case .missed: String(localized: .assignmentsGroupMissed)
        }
    }
}
