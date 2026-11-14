import Foundation

public enum MaterialRole: String, Codable, Sendable, CaseIterable {
    case syllabus, lecture, exercise, textbook, inherited, assignment, lab, exam, study, archive, other

    public init?(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, let folder = CourseFolder(rawValue: parts[0]) else { return nil }
        switch folder {
        case .syllabus: self = .syllabus
        case .lectures: self = .lecture
        case .exercises: self = .exercise
        case .textbooks: self = .textbook
        case .inherited: self = .inherited
        case .study: self = .study
        case .archive: self = .archive
        case .assignments:
            guard parts.count >= 3 else { return nil }
            self = StandardLayout.assignmentFolder(parts[1])?.prefix == AssignmentKind.lab.rawValue ? .lab : .assignment
        case .exams:
            guard parts.count >= 3 else { return nil }
            self = .exam
        case .notes, .ink, .recordings, .metadata:
            return nil
        }
    }
}

extension MaterialRole {
    // 폴더를 출처별로 나누기 전(course.json v4)의 역할 이름이다. v5 마이그레이션이 이 이름을 바꾸지만, 그보다 먼저
    // 파일 전체를 디코딩하는 이전 마이그레이션도 이 이름을 읽어야 한다.
    public static let legacy: [String: MaterialRole] = ["pastExam": .inherited, "examPrep": .exam]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let role = MaterialRole(rawValue: raw) ?? Self.legacy[raw] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown material role \(raw)"))
        }
        self = role
    }
}
