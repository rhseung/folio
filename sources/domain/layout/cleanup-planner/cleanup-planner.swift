import Foundation

public enum CleanupPlanner {
    enum LegacyFolder {
        case lectures, assignments(AssignmentKind), labManuals, labReports, pastExams(source: String?), examReview, textbooks, notes
    }

    static let adminFolderNames: Set<String> = ["학사"]
    static let examReviewFolder = "Exam Review"

    public static func selfMade(moves: [(from: String, to: String)]) -> Set<String> {
        var paths = Set<String>()
        for (from, to) in moves {
            if from.split(separator: "/").contains(Substring(examReviewFolder)) {
                paths.insert(to)
                continue
            }
            for path in paths where path == from || path.hasPrefix(from + "/") {
                paths.remove(path)
                paths.insert(to + path.dropFirst(from.count))
            }
        }
        return paths
    }

    static func legacyFolder(_ name: String, siblings: Set<String>) -> LegacyFolder? {
        switch name {
        case "강의자료": return .lectures
        case "숙제", "Homeworks": return .assignments(.homework)
        case "Slow Problems": return .assignments(.slowProblem)
        case "Reports": return siblings.contains("Manuals") ? .labReports : .assignments(.report)
        case "Manuals": return .labManuals
        case examReviewFolder: return .examReview
        case "Books": return .textbooks
        case "노트": return .notes
        default:
            guard name.hasPrefix("족보") else { return nil }
            let source = name.firstMatch(of: /\((.+)\)/).map { String($0.1) }
            return .pastExams(source: source)
        }
    }

    public static func plan(
        _ gist: FolderTree, skip: Set<String> = [], labs: [String: [String: Int]] = [:],
        labWeeks: [String: [Int: Int]] = [:], selfMade: Set<String> = [],
        exams: [String: [Exam]] = [:]
    ) -> CleanupPlan {
        var moves: [PlannedMove] = []
        var skipped: [String] = []
        var removals: [String] = []

        func isSkipped(_ path: String) -> Bool {
            skip.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        for semester in gist.children where semester.name != StandardLayout.metadataFolder && semester.name != StandardLayout.creditedFolder
        {
            guard SemesterFolder(name: semester.name) != nil, !semester.isFile, !isSkipped(semester.name) else {
                skipped.append(semester.name)
                continue
            }
            let admin = "\(semester.name)/\(StandardLayout.adminFolder)"
            for child in semester.children {
                let path = "\(semester.name)/\(child.name)"
                if isSkipped(path) {
                    skipped.append(path)
                } else if child.isFile {
                    moves.append(.init(from: path, to: "\(admin)/\(child.name)"))
                } else if adminFolderNames.contains(child.name) {
                    moves += child.children.map { .init(from: "\(path)/\($0.name)", to: "\(admin)/\($0.name)") }
                } else if child.name == StandardLayout.adminFolder {
                    continue
                } else if StandardLayout.isCourseFolderName(child.name) {
                    let mine = Set(selfMade.filter { $0.hasPrefix(path + "/") }.map { String($0.dropFirst(path.count + 1)) })
                    var planner = CoursePlanner(
                        course: child, labs: labs[path] ?? [:], labWeeks: labWeeks[path] ?? [:], selfMade: mine,
                        exams: exams[path])
                    moves += planner.plan().map {
                        .init(from: "\(path)/\($0.from)", to: "\(path)/\($0.to)", review: $0.review, exam: $0.exam, kind: $0.kind)
                    }
                    removals += planner.removals.map { "\(path)/\($0)" }
                } else {
                    skipped.append(path)
                }
            }
        }
        return CleanupPlan(moves: moves.filter { $0.from != $0.to }, skipped: skipped, removals: removals)
    }
}
