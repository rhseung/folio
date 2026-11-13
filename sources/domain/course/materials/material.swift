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

public enum MaterialKind: String, Codable, Sendable, CaseIterable {
    case problem, solution, submission, slides, book, syllabus, pastExam, other
}

public enum MaterialStatus: String, Codable, Sendable, CaseIterable {
    case classified, unclassified, missing, ignored
}

public struct Material: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var path: String
    public var isFolder: Bool
    public var bookmark: Data?
    public var hash: String?
    public var size: Int64?
    public var role: MaterialRole?
    public var kind: MaterialKind?
    public var sourceOf: UUID?
    public var builtHash: String?
    public var solutionOf: UUID?
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
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

extension Material {
    // `examIds`는 course.json v5에서 추가했다. v5 이전 마이그레이션도 파일 전체를 디코딩하므로, 이 값이 없어도
    // 읽히도록 디코더를 직접 쓴다.
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
