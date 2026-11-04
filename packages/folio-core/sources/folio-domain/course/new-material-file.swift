import Foundation

/// A file made from nothing in the materials screen, such as `hw4.tex` in an assignment's folder.
public enum NewMaterialFile {
    /// The user's own folders. A received folder holds only what was received, and a course's top and `Assignments` or
    /// `Exams` hold folders only.
    public static func accepts(folder: String) -> Bool {
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy(isFileName), let top = CourseFolder(rawValue: parts[0]) else { return false }
        switch top {
        case .study, .archive: return true
        case .assignments, .exams: return parts.count >= 2
        default: return false
        }
    }

    /// Study and Archive, then each assignment's and exam's folder, made or not yet: the first file makes the folder.
    public static func places(assignments: [Assignment], exams: [Exam], assignmentFolders: [String]) -> [String] {
        var seen = Set<String>()
        let all = [CourseFolder.study.rawValue, CourseFolder.archive.rawValue]
            + (assignmentFolders.map { "\(CourseFolder.assignments.rawValue)/\($0)" } + assignments.map(AssignmentFiles.path(of:)))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            + exams.compactMap(MaterialIntake.folder(of:))
        return all.filter { accepts(folder: $0) && seen.insert($0).inserted }
    }

    /// One path component that Finder shows: no separator, not hidden, not `..`.
    public static func isFileName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespaces) && !name.contains("/") && !name.contains(":") && !name.hasPrefix(".")
    }

    /// A `.tex` that builds as it is; any other format starts empty.
    public static func text(for name: String) -> String {
        MaterialFormat(path: name) == .tex ? TexDocument.wrap([""]) : ""
    }
}

/// The document every `.tex` Folio makes starts from, notes and materials alike.
public enum TexDocument {
    /// kotex because the user writes Korean; the AMS packages because most of it is math.
    static let preamble = ["\\documentclass[11pt]{article}", "\\usepackage{kotex}", "\\usepackage{amsmath, amssymb, amsthm}", "", "\\begin{document}"]

    public static func wrap(_ body: [String]) -> String {
        (preamble + body + ["\\end{document}"]).joined(separator: "\n") + "\n"
    }
}
