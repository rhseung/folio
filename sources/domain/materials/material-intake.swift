import Foundation

public enum MaterialIntake {
    public static func lectureName(_ name: String, week: Int) -> String {
        StandardLayout.isLectureFileName(name) ? name : String(format: "%02d_", week) + name
    }

    public static func name(_ source: String, in folder: String, session: Session?) -> String {
        guard folder == CourseFolder.lectures.rawValue, let session else { return source }
        return lectureName(source, week: session.week)
    }

    public struct Placement: Equatable, Sendable {
        public var folder: String
        public var name: String
        public var prefix: String?
        public var suffix: String?

        public var path: String { "\(folder)/\(name)" }
    }

    // 한 번에 정해야 같은 이름으로 들어오는 두 파일도 하나씩 복사할 때처럼 ` 2`를 받는다.
    public static func plan(_ items: [(source: String, folder: String, session: Session?)], taken: (String) -> Set<String>) -> [Placement] {
        var held: [String: Set<String>] = [:]
        return items.map { item in
            let named = name(item.source, in: item.folder, session: item.session)
            let had = held[item.folder] ?? taken(item.folder)
            let free = freeName(named, taken: had)
            held[item.folder] = had.union([free])
            let base = { (name: String) in (name as NSString).deletingPathExtension }
            return Placement(
                folder: item.folder, name: free,
                prefix: named == item.source ? nil : String(named.dropLast(item.source.count)),
                suffix: free == named ? nil : String(base(free).dropFirst(base(named).count)))
        }
    }

    public static func freeName(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        while taken.contains(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)") { n += 1 }
        return ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
    }

    public static func places(assignmentFolders: [String]) -> [String] {
        [CourseFolder.syllabus, .exercises, .textbooks, .inherited, .study, .archive].map(\.rawValue)
            + assignmentFolders.map { "\(CourseFolder.assignments.rawValue)/\($0)" }
    }

    public static func folder(of exam: Exam) -> String? {
        exam.folder.map { "\(CourseFolder.exams.rawValue)/\($0)" }
    }

    public static func examFolder(title: String, among exams: [Exam]) -> String {
        examFolder(title: title, taken: Set(exams.compactMap(\.folder)))
    }

    public static func examFolder(title: String, taken: Set<String>) -> String {
        var name = title.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(".") { name = String(name.drop { $0 == "." }) }
        return freeName(name.isEmpty ? "Exam" : name, taken: taken.union([StandardLayout.legacyPastExamsFolder]))
    }
}
