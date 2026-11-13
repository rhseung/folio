import Foundation

public enum Term: String, CaseIterable, Codable, Sendable {
    case spring, summer, fall, winter
    case credited

    public var folderNumber: Int? {
        switch self {
        case .spring: 1
        case .summer: 2
        case .fall: 3
        case .winter: 4
        case .credited: nil
        }
    }
}

public struct SemesterFolder: Hashable, Sendable {
    public let year: Int
    public let term: Term
    public let name: String

    public init?(year: Int, term: Term) {
        guard (1000...9999).contains(year), let number = term.folderNumber else { return nil }
        self.year = year
        self.term = term
        self.name = "\(year)-\(number)"
    }

    public init?(name: String) {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let year = Int(parts[0]), let number = Int(parts[1]),
            let term = Term.allCases.first(where: { $0.folderNumber == number }),
            let parsed = SemesterFolder(year: year, term: term),
            parsed.name == name  // `2026-03`이나 `+2026-3` 같은 비표준 꼴을 거절한다.
        else { return nil }
        self = parsed
    }
}

public enum CourseFolder: String, CaseIterable, Sendable {
    case syllabus = "Syllabus"
    case lectures = "Lectures"
    case exercises = "Exercises"
    case textbooks = "Textbooks"
    case inherited = "Inherited"
    case assignments = "Assignments"
    case exams = "Exams"
    case study = "Study"
    case notes = "Notes"
    case ink = "Ink"
    case recordings = "Recordings"
    case archive = "Archive"
    case metadata = ".folio"

    public var holdsMaterials: Bool {
        switch self {
        case .notes, .ink, .recordings, .metadata: false
        default: true
        }
    }
}

public enum AssignmentKind: String, CaseIterable, Codable, Sendable {
    case homework = "HW"
    case lab = "Lab"
    case report = "Report"
    case project = "Project"
    case slowProblem = "SP"
    case reading = "Reading"
}

public enum StandardLayout {
    public static let metadataFolder = CourseFolder.metadata.rawValue
    public static let adminFolder = "_Admin"
    public static let creditedFolder = "_Credited"
    public static let legacyPastExamsFolder = "Past"
    public static let quizFolderPrefix = "Quiz"
    public static let midtermFolder = "Midterm"
    public static let finalFolder = "Final"
    public static let noteAssetsFolder = "assets"
    public static let legacyNoteExportsFolder = "Exports"

    public static let transcriptFile = "transcript.json"
    public static let catalogFile = "catalog.json"
    public static let settingsFile = "settings.json"
    public static let courseFile = "course.json"
    public static let movesFile = "moves.jsonl"
    public static let logsFolder = "logs"
    public static let quizzesFolder = "quizzes"
    public static let chatsFolder = "chats"
    public static let widgetsFolder = "widgets"
    public static let logExtension = "jsonl"

    public static func courseFolderName(prefix: String, number: String, title: String) -> String? {
        let digits = number.split(separator: "-").first.map(String.init) ?? number
        let cleaned = title.map { "/\\:".contains($0) ? "-" : $0 }
        let name = "\(prefix)\(digits) \(String(cleaned).trimmingCharacters(in: .whitespaces))"
        return isCourseFolderName(name) ? name : nil
    }

    public static func widgetFile(_ id: UUID, noteFolder: URL) -> URL? {
        let parts = noteFolder.standardizedFileURL.pathComponents
        guard
            let notes = parts.indices.first(where: {
                $0 > 0 && parts[$0] == CourseFolder.notes.rawValue && isCourseFolderName(parts[$0 - 1])
            })
        else { return nil }
        var course = noteFolder.standardizedFileURL
        for _ in notes..<parts.count { course.deleteLastPathComponent() }
        return course.appending(path: NoteWidget.path(id))
    }

    public static func creditedFolder(source: String) -> String? {
        isCreditedSourceName(source) ? "\(creditedFolder)/\(source)" : nil
    }

    public static func isCreditedSourceName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespaces) && !name.contains("/") && !name.contains(":")
            && !name.hasPrefix(".")
    }

    public enum NoteFolderProblem: Sendable, Equatable {
        case empty
        case nested
        case reserved
        case hidden
    }

    // 과목 폴더는 대소문자를 가리지 않는 볼륨에 있어 `Assets`도 같은 폴더이므로, `assets`와 `Exports`는 대소문자를
    // 무시하고 비교한다.
    public static func noteFolderProblem(_ name: String) -> NoteFolderProblem? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return .empty }
        if name.contains("/") || name.contains(":") { return .nested }
        if name.hasPrefix(".") { return .hidden }
        if [noteAssetsFolder, legacyNoteExportsFolder].contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return .reserved
        }
        return nil
    }

    public static func isCourseFolderName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Z]{2,}\d{3,4} \S.*/) != nil
    }

    public static func isLectureFileName(_ name: String) -> Bool {
        lectureWeek(name) != nil
    }

    public static func lectureWeek(_ name: String) -> Int? {
        name.wholeMatch(of: /(\d{2})(-\d+)?_.+/).flatMap { Int($0.1) }
    }

    public static func isExamFolderName(_ name: String) -> Bool {
        if name == midtermFolder || name == finalFolder { return true }
        return name.hasPrefix(quizFolderPrefix) && Int(name.dropFirst(quizFolderPrefix.count)).map { $0 > 0 } == true
    }

    public static func assignmentFolder(_ name: String, extraPrefixes: [String] = []) -> (prefix: String, number: Int)? {
        guard let match = name.wholeMatch(of: /([A-Za-z]+)(\d{2})/),
            let number = Int(match.2)
        else { return nil }
        let prefix = String(match.1)
        let known = AssignmentKind.allCases.map(\.rawValue) + extraPrefixes
        return known.contains(prefix) ? (prefix, number) : nil
    }
}
