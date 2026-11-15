import FolioDomain
import Foundation

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MaterialRole {
    var label: String {
        switch self {
        case .syllabus: String(localized: .materialRoleSyllabus)
        case .lecture: String(localized: .materialRoleLecture)
        case .exercise: String(localized: .materialRoleExercise)
        case .textbook: String(localized: .materialRoleTextbook)
        case .assignment: String(localized: .materialRoleAssignment)
        case .lab: String(localized: .materialRoleLab)
        case .inherited: String(localized: .materialRoleInherited)
        case .exam: String(localized: .materialRoleExam)
        case .study: String(localized: .materialRoleStudy)
        case .archive: String(localized: .materialRoleArchive)
        case .other: String(localized: .materialRoleOther)
        }
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

extension Lateness {
    var label: String {
        ceiling.map { String(localized: .assignmentsLateCeiling(days, Int(($0 * 100).rounded()))) }
            ?? String(localized: .assignmentsLate(days))
    }
}

extension LateRule {
    var label: String {
        let percent = percentPerDay.formatted(.number.grouping(.never))
        return days.map { String(localized: .lateRuleSummaryDays(percent, $0)) } ?? String(localized: .lateRuleSummary(percent))
    }
}
