import Foundation

/// Where files brought into a course from outside go, and what they are called.
public enum MaterialIntake {
    /// `05_<name>` for a file brought in for a week-5 session, so `Lectures` keeps its week order.
    public static func lectureName(_ name: String, week: Int) -> String {
        StandardLayout.isLectureFileName(name) ? name : String(format: "%02d_", week) + name
    }

    /// What a file brought into `folder` for `session` is called there. Only `Lectures` puts the session's week in
    /// front; elsewhere the name is the professor's and stays.
    public static func name(_ source: String, in folder: String, session: Session?) -> String {
        guard folder == CourseFolder.lectures.rawValue, let session else { return source }
        return lectureName(source, week: session.week)
    }

    /// Where one incoming file lands. `prefix` and `suffix` are the parts added to its own name: `05_` for a lecture's
    /// week, ` 2` past a name the folder already holds.
    public struct Placement: Equatable, Sendable {
        public var folder: String
        public var name: String
        public var prefix: String?
        public var suffix: String?

        public var path: String { "\(folder)/\(name)" }
    }

    /// Every file's final name in one pass, so two incoming files with one name also get ` 2`, as copying them one by
    /// one does. `taken` gives what a folder holds now.
    public static func plan(_ items: [(source: String, folder: String, session: Session?)], taken: (String) -> Set<String>) -> [Placement] {
        var held: [String: Set<String>] = [:]
        return items.map { item in
            let named = name(item.source, in: item.folder, session: item.session)
            let had = held[item.folder] ?? taken(item.folder)
            let free = freeName(named, taken: had)
            held[item.folder] = had.union([free])
            let base = { (name: String) in (name as NSString).deletingPathExtension }
            return Placement(folder: item.folder, name: free,
                             prefix: named == item.source ? nil : String(named.dropLast(item.source.count)),
                             suffix: free == named ? nil : String(base(free).dropFirst(base(named).count)))
        }
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
        [CourseFolder.syllabus, .exercises, .textbooks, .inherited, .study, .archive].map(\.rawValue)
            + assignmentFolders.map { "\(CourseFolder.assignments.rawValue)/\($0)" }
    }

    /// An exam's own folder. It is made by the first file put in it, so an exam without files leaves no empty folder.
    public static func folder(of exam: Exam) -> String? {
        exam.folder.map { "\(CourseFolder.exams.rawValue)/\($0)" }
    }

    /// A new exam's folder: its title made safe for a path, numbered past the folders other exams (and a legacy `Past`) hold.
    public static func examFolder(title: String, among exams: [Exam]) -> String {
        examFolder(title: title, taken: Set(exams.compactMap(\.folder)))
    }

    public static func examFolder(title: String, taken: Set<String>) -> String {
        var name = title.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(".") { name = String(name.drop { $0 == "." }) }
        return freeName(name.isEmpty ? "Exam" : name, taken: taken.union([StandardLayout.legacyPastExamsFolder]))
    }
}
