// Single source of truth for folder and file names (AGENTS.md "폴더 구조와 이름 규칙").
// Other layers derive names from these types; never spell the strings elsewhere.

import Foundation

public enum Term: String, CaseIterable, Codable, Sendable {
    case spring, summer, fall, winter
    /// 인정학기: credits earned before or outside GIST. Its courses live under `_Credited/<source>`, not a term folder.
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

/// `<year>-<term number>`, e.g. `2026-3`.
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
              parsed.name == name  // rejects non-canonical forms like `2026-03` or `+2026-3`
        else { return nil }
        self = parsed
    }
}

public enum CourseFolder: String, CaseIterable, Sendable {
    case syllabus = "Syllabus"
    case lectures = "Lectures"
    case exercises = "Exercises"
    case textbooks = "Textbooks"
    case assignments = "Assignments"
    case exams = "Exams"
    case notes = "Notes"
    case ink = "Ink"
    /// Lecture recordings and their transcripts.
    case recordings = "Recordings"
    case archive = "Archive"
    case metadata = ".folio"

    /// Files here are tracked as Material. Notes, Ink and metadata are tracked by their own entities.
    public var holdsMaterials: Bool {
        switch self {
        case .notes, .ink, .recordings, .metadata: false
        default: true
        }
    }
}

/// Folder-name prefixes under `Assignments/`, e.g. `HW03`.
public enum AssignmentKind: String, CaseIterable, Codable, Sendable {
    case homework = "HW"
    case lab = "Lab"
    case report = "Report"
    case project = "Project"
    case slowProblem = "SP"
    case reading = "Reading"
}

public enum StandardLayout {
    /// Same name at the GIST root and inside each course.
    public static let metadataFolder = CourseFolder.metadata.rawValue
    public static let adminFolder = "_Admin"
    /// At the GIST root: `_Credited/<source>/<course>` for credited terms, named by where the credits came from
    /// (`영재고 AP`) because a year says little about them. The `_` keeps it apart from term folders.
    public static let creditedFolder = "_Credited"
    public static let pastExamsFolder = "Past"
    public static let quizFolderPrefix = "Quiz"
    /// What exam folders were called before an exam kept its own folder name; cleanup still sorts legacy material into them.
    public static let midtermFolder = "Midterm"
    public static let finalFolder = "Final"
    /// Inside `Notes/`: files the notes embed, and notes exported to PDF.
    public static let noteAssetsFolder = "assets"
    public static let noteExportsFolder = "Exports"

    // Inside `.folio/`
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

    /// `EC` + `4207-01` + `그래프 이론` → `EC4207 그래프 이론`. Nil when the result would not pass `isCourseFolderName`.
    public static func courseFolderName(prefix: String, number: String, title: String) -> String? {
        let digits = number.split(separator: "-").first.map(String.init) ?? number
        let cleaned = title.map { "/\\:".contains($0) ? "-" : $0 }
        let name = "\(prefix)\(digits) \(String(cleaned).trimmingCharacters(in: .whitespaces))"
        return isCourseFolderName(name) ? name : nil
    }

    /// `<course>/.folio/widgets/<id>.html` for a note in `<course>/Notes`, at any depth below it.
    public static func widgetFile(_ id: UUID, noteFolder: URL) -> URL? {
        let parts = noteFolder.standardizedFileURL.pathComponents
        guard let notes = parts.indices.first(where: { $0 > 0 && parts[$0] == CourseFolder.notes.rawValue && isCourseFolderName(parts[$0 - 1]) })
        else { return nil }
        var course = noteFolder.standardizedFileURL
        for _ in notes..<parts.count { course.deleteLastPathComponent() }
        return course.appending(path: metadataFolder).appending(path: widgetsFolder).appending(path: id.uuidString + ".html")
    }

    /// `_Credited/<source>`. Nil when the source can't be a folder name.
    public static func creditedFolder(source: String) -> String? {
        isCreditedSourceName(source) ? "\(creditedFolder)/\(source)" : nil
    }

    /// A single folder name: not empty, no path separators, not hidden.
    public static func isCreditedSourceName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespaces) && !name.contains("/") && !name.contains(":") && !name.hasPrefix(".")
    }

    /// `<code> <title>`, e.g. `EC4207 그래프 이론`.
    public static func isCourseFolderName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Z]{2,}\d{3,4} \S.*/) != nil
    }

    /// `<two-digit week>_<title>`, or `05-1_<title>` when a week has several files.
    public static func isLectureFileName(_ name: String) -> Bool {
        lectureWeek(name) != nil
    }

    public static func lectureWeek(_ name: String) -> Int? {
        name.wholeMatch(of: /(\d{2})(-\d+)?_.+/).flatMap { Int($0.1) }
    }

    /// `<year> <Midterm|Final|Quiz> (<source>)`, optionally followed by ` Solution`.
    public static func isPastExamFileName(_ name: String) -> Bool {
        name.wholeMatch(of: /\d{4} (Midterm|Final|Quiz)( \(.+\))?( Solution)?\.[^.]+/) != nil
    }

    /// `Midterm`, `Final`, `Quiz1`, ... (one folder per Exam), plus `Past`.
    public static func isExamFolderName(_ name: String) -> Bool {
        if name == pastExamsFolder || name == midtermFolder || name == finalFolder { return true }
        return name.hasPrefix(quizFolderPrefix) && Int(name.dropFirst(quizFolderPrefix.count)).map { $0 > 0 } == true
    }

    /// `<prefix><two digits>`, e.g. `HW03`, `Lab01`.
    public static func assignmentFolder(_ name: String, extraPrefixes: [String] = []) -> (prefix: String, number: Int)? {
        guard let match = name.wholeMatch(of: /([A-Za-z]+)(\d{2})/),
              let number = Int(match.2) else { return nil }
        let prefix = String(match.1)
        let known = AssignmentKind.allCases.map(\.rawValue) + extraPrefixes
        return known.contains(prefix) ? (prefix, number) : nil
    }
}
