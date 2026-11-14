import Foundation

public enum AssignmentKind: String, CaseIterable, Codable, Sendable {
    case homework = "HW"
    case lab = "Lab"
    case report = "Report"
    case project = "Project"
    case slowProblem = "SP"
    case reading = "Reading"
}
