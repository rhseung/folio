import Foundation

/// Where files brought into a course from outside go, and what they are called.
public enum MaterialIntake {
    /// `05_<name>` for a file brought in for a week-5 session, so `Lectures` keeps its week order.
    public static func lectureName(_ name: String, week: Int) -> String {
        StandardLayout.isLectureFileName(name) ? name : String(format: "%02d_", week) + name
    }

    /// `name`, or `name 2.ext`, `name 3.ext`… — the first one not in `taken`, so a copy never overwrites.
    public static func freeName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        while taken.contains(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)") { n += 1 }
        return ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
    }

    /// Standard folders a file can be put in by hand, course-relative. `Lectures` is left to session rows,
    /// which know the week its name needs.
    public static func places(assignmentFolders: [String]) -> [String] {
        [CourseFolder.syllabus, .exercises, .textbooks, .archive].map(\.rawValue)
            + ["\(CourseFolder.exams.rawValue)/\(StandardLayout.pastExamsFolder)"]
            + assignmentFolders.map { "\(CourseFolder.assignments.rawValue)/\($0)" }
    }

    public static func folder(of exam: Exam) -> String? {
        exam.folder.map { "\(CourseFolder.exams.rawValue)/\($0)" }
    }

    /// A new exam's folder: its title made safe for a path, numbered past the folders other exams (and `Past`) hold.
    public static func examFolder(title: String, among exams: [Exam]) -> String {
        var name = title.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(".") { name = String(name.drop { $0 == "." }) }
        let taken = Set(exams.compactMap(\.folder) + [StandardLayout.pastExamsFolder])
        return freeName(name.isEmpty ? "Exam" : name, taken: taken)
    }
}
