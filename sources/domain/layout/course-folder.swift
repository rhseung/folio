import Foundation

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
