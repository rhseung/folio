import Foundation

public enum MaterialIntake {
    public struct Placement: Equatable, Sendable {
        public var folder: String
        public var name: String
        public var suffix: String?

        public var path: String { "\(folder)/\(name)" }
    }

    // 한 번에 정해야 같은 이름으로 들어오는 두 파일도 하나씩 복사할 때처럼 ` 2`를 받는다.
    public static func plan(_ items: [(source: String, folder: String)], taken: (String) -> Set<String>) -> [Placement] {
        var held: [String: Set<String>] = [:]
        return items.map { item in
            let had = held[item.folder] ?? taken(item.folder)
            let free = freeName(item.source, taken: had)
            held[item.folder] = had.union([free])
            let base = { (name: String) in (name as NSString).deletingPathExtension }
            return Placement(
                folder: item.folder, name: free,
                suffix: free == item.source ? nil : String(base(free).dropFirst(base(item.source).count)))
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
