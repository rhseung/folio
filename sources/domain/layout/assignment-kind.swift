import Foundation

public enum AssignmentKind: String, CaseIterable, Codable, Sendable {
    case homework = "HW"
    case lab = "Lab"
    case report = "Report"
    case project = "Project"
    case slowProblem = "SP"
    case reading = "Reading"
}

extension AssignmentKind {
    public static let builtIn = allCases

    static func mentioned(in name: String, kinds: [AssignmentKind]) -> FileRule.Match? {
        let keyword =
            /(?:^|[^a-z])((hw|homework|assignment|assign|lab|sp|slow[\s_-]?problems?|report|project|reading|과제|숙제)[\s_-]*(\d{1,2}))(?!\d)/
        guard let m = name.firstMatch(of: keyword.ignoresCase()), let number = Int(m.3) else { return nil }
        let kind: AssignmentKind =
            switch m.2.lowercased() {
            case "lab": .lab
            case "report": .report
            case "project": .project
            case "reading": .reading
            case let word where word == "sp" || word.hasPrefix("slow"): .slowProblem
            default: .homework
            }
        return FileRule.Match(words: String(m.1), number: number, assignment: kind)
    }
}
