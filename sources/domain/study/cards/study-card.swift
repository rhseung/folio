import FolioCore
import Foundation

// 그대로 기억할 것(정의, 정리의 내용, 공식)을 담는 앞뒤 카드다. 푸는 연습은 문제가 맡는다.
public struct StudyCard: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var unitId: UUID
    // 마크다운이고 수식은 LaTeX다.
    public var front: String
    public var back: String
    public var source: CardSource
    public var materialId: UUID?
    public var page: Int?
    public var noteId: UUID?
    public var noteBlockId: String?
    // 카드를 만들 때 원본 블록의 해시다. 블록이 바뀌면 "원본 변경됨"을 보인다.
    public var noteBlockHash: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, unitId: UUID, front: String, back: String, source: CardSource = .manual
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.unitId = unitId
        self.front = front
        self.back = back
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        updatedBy =
            try c.decodeIfPresent(DeviceID.self, forKey: .updatedBy) ?? DeviceID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        unitId = try c.decode(UUID.self, forKey: .unitId)
        front = try c.decode(String.self, forKey: .front)
        back = try c.decode(String.self, forKey: .back)
        source = try c.decodeIfPresent(CardSource.self, forKey: .source) ?? .manual
        materialId = try c.decodeIfPresent(UUID.self, forKey: .materialId)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        noteId = try c.decodeIfPresent(UUID.self, forKey: .noteId)
        noteBlockId = try c.decodeIfPresent(String.self, forKey: .noteBlockId)
        noteBlockHash = try c.decodeIfPresent(String.self, forKey: .noteBlockHash)
    }
}
