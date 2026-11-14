import Foundation

public enum NewMaterialFile {
    public static func accepts(folder: String) -> Bool {
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(isFileName), let top = CourseFolder(rawValue: parts[0]) else { return false }
        switch top {
        case .study, .archive: return true
        case .assignments, .exams: return parts.count >= 2
        default: return false
        }
    }

    public static func accepts(folder: String, places: [String]) -> Bool {
        guard accepts(folder: folder) else { return false }
        let parts = folder.split(separator: "/").map(String.init)
        guard parts[0] == CourseFolder.assignments.rawValue || parts[0] == CourseFolder.exams.rawValue else { return true }
        return places.contains(parts.prefix(2).joined(separator: "/"))
    }

    public static func places(assignments: [Assignment], exams: [Exam], assignmentFolders: [String]) -> [String] {
        var seen = Set<String>()
        let all =
            [CourseFolder.study.rawValue, CourseFolder.archive.rawValue]
            + (assignmentFolders.map { "\(CourseFolder.assignments.rawValue)/\($0)" } + assignments.map(AssignmentFiles.path(of:)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            + exams.compactMap(MaterialIntake.folder(of:))
        return all.filter { accepts(folder: $0) && seen.insert($0).inserted }
    }

    public static func defaultPlace(assignments: [Assignment], places: [String]) -> String? {
        let newest = assignments.map { ($0, AssignmentFiles.path(of: $0)) }
            .filter { places.contains($0.1) }
            .max { a, b in (a.0.due ?? a.0.createdAt, a.0.createdAt) < (b.0.due ?? b.0.createdAt, b.0.createdAt) }
        return newest?.1 ?? places.first
    }

    public static func isFileName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespaces) && !name.contains("/") && !name.contains(":")
            && !name.hasPrefix(".")
    }

    public static func text(for name: String) -> String {
        MaterialFormat(path: name) == .tex ? TexDocument.wrap([""]) : ""
    }
}

public enum TexDocument {
    static let preamble = [
        "\\documentclass[11pt]{article}", "\\usepackage{kotex}", "\\usepackage{amsmath, amssymb, amsthm}", "", "\\begin{document}",
    ]

    public static func wrap(_ body: [String]) -> String {
        (preamble + body + ["\\end{document}"]).joined(separator: "\n") + "\n"
    }
}
