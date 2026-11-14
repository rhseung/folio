import Foundation

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
