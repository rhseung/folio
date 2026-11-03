import Foundation

public enum MaterialRole: String, Codable, Sendable, CaseIterable {
    case syllabus, lecture, exercise, textbook, inherited, assignment, lab, exam, study, archive, other

    /// The role implied by where a file sits (`path` relative to the course folder), or nil outside role folders.
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

public enum MaterialKind: String, Codable, Sendable, CaseIterable {
    /// `pastExam` is a past exam paper or its solution, wherever it sits; usually under `Inherited`.
    case problem, solution, submission, slides, book, syllabus, pastExam, other
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
    /// For a PDF: its hash when `material build` last wrote it. Any other hash means the PDF came from somewhere else
    /// (a professor, another TeX), and a build asks before replacing it.
    public var builtHash: String?
    public var solutionOf: UUID?
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
    /// Exams this file was made or kept for. A file in an exam's own folder belongs to it without a link.
    public var examIds: [UUID]
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
        self.examIds = []
        self.status = status
    }
}

extension MaterialRole {
    /// Roles before folders were split by origin (course.json v4). The v5 migration renames them, but an older
    /// migration that decodes the whole file runs first and must read them too.
    public static let legacy: [String: MaterialRole] = ["pastExam": .inherited, "examPrep": .exam]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let role = MaterialRole(rawValue: raw) ?? Self.legacy[raw] else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown material role \(raw)"))
        }
        self = role
    }
}

extension Material {
    /// Written out so `examIds`, added in course.json v5, may be absent: migrations before v5 decode the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(DeviceID.self, forKey: .updatedBy)
        path = try c.decode(String.self, forKey: .path)
        isFolder = try c.decode(Bool.self, forKey: .isFolder)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
        role = try c.decodeIfPresent(MaterialRole.self, forKey: .role)
        kind = try c.decodeIfPresent(MaterialKind.self, forKey: .kind)
        sourceOf = try c.decodeIfPresent(UUID.self, forKey: .sourceOf)
        builtHash = try c.decodeIfPresent(String.self, forKey: .builtHash)
        solutionOf = try c.decodeIfPresent(UUID.self, forKey: .solutionOf)
        sessionIds = try c.decode([UUID].self, forKey: .sessionIds)
        unitIds = try c.decode([UUID].self, forKey: .unitIds)
        examIds = try c.decodeIfPresent([UUID].self, forKey: .examIds) ?? []
        status = try c.decode(MaterialStatus.self, forKey: .status)
    }
}
