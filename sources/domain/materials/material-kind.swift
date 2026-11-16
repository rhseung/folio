import Foundation

public enum MaterialKind: String, Codable, Sendable, CaseIterable {
    case problem, solution, submission, slides, book, syllabus, pastExam, other
}
