import Foundation

public enum MaterialRole: String, Codable, Sendable, CaseIterable {
    case syllabus, lecture, exercise, textbook, assignment, lab, pastExam, examPrep, archive, other

    /// The role implied by where a file sits (`path` relative to the course folder), or nil outside role folders.
    public init?(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, let folder = CourseFolder(rawValue: parts[0]) else { return nil }
        switch folder {
        case .syllabus: self = .syllabus
        case .lectures: self = .lecture
        case .exercises: self = .exercise
        case .textbooks: self = .textbook
        case .archive: self = .archive
        case .assignments:
            guard parts.count >= 3 else { return nil }
            self = StandardLayout.assignmentFolder(parts[1])?.prefix == AssignmentKind.lab.rawValue ? .lab : .assignment
        case .exams:
            guard parts.count >= 3 else { return nil }
            self = parts[1] == StandardLayout.pastExamsFolder ? .pastExam : .examPrep
        case .notes, .ink, .recordings, .metadata:
            return nil
        }
    }
}

public enum MaterialKind: String, Codable, Sendable, CaseIterable {
    case problem, solution, submission, slides, book, syllabus, other
}

public enum MaterialStatus: String, Codable, Sendable, CaseIterable {
    case classified, unclassified, missing, ignored
}

/// A tracked file (or code-project folder) in a course folder. Identified by `id`; `path` is only the last place it was seen.
public struct Material: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    /// Relative to the course folder, `/`-separated.
    public var path: String
    public var isFolder: Bool
    public var bookmark: Data?
    /// SHA-256 hex. Nil until the file is downloaded from iCloud, and for folders.
    public var hash: String?
    public var size: Int64?
    public var role: MaterialRole?
    public var kind: MaterialKind?
    /// The PDF this `.tex` file is the source of.
    public var sourceOf: UUID?
    public var solutionOf: UUID?
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
    public var status: MaterialStatus

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date,
        path: String, isFolder: Bool = false, bookmark: Data? = nil, hash: String? = nil, size: Int64? = nil,
        role: MaterialRole? = nil, kind: MaterialKind? = nil, status: MaterialStatus
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.path = path
        self.isFolder = isFolder
        self.bookmark = bookmark
        self.hash = hash
        self.size = size
        self.role = role
        self.kind = kind
        self.sessionIds = []
        self.unitIds = []
        self.status = status
    }
}
