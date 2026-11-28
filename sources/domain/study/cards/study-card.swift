import FolioCore
import Foundation

// 그대로 기억할 것(정의, 정리의 내용, 공식)을 담는 개념 카드다. 푸는 연습은 문제가 맡는다.
public struct StudyCard: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var unitId: UUID
    public var kind: CardKind
    // 마크다운이고 수식은 LaTeX다. 참·거짓 카드는 앞이 문장이고 뒤가 답을 고른 뒤에 보이는 이유 한 줄이다.
    public var front: String
    public var back: String
    // 참·거짓 카드의 답이다. 앞뒤 카드에는 없다.
    public var answer: Bool?
    public var source: CardSource
    public var materialId: UUID?
    public var page: Int?
    public var noteId: UUID?
    // 카드를 이은 노트의 절이다. 노트 링크의 `#제목`과 같은 값(`NoteOutline`의 anchor)이라, 제목을 고치거나 지우면 찾지 못하고
    // 카드는 노트에만 이어진 것으로 본다.
    public var noteSection: String?
    public var noteBlockId: String?
    // 카드를 만들 때 원본 블록의 해시다. 블록이 바뀌면 "원본 변경됨"을 보인다.
    public var noteBlockHash: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, unitId: UUID, kind: CardKind = .flip, front: String, back: String,
        answer: Bool? = nil, source: CardSource = .manual
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.unitId = unitId
        self.kind = kind
        self.front = front
        self.back = back
        self.answer = kind == .trueFalse ? answer : nil
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
        // 형식이 생기기 전의 카드는 앞뒤 카드다.
        kind = try c.decodeIfPresent(CardKind.self, forKey: .kind) ?? .flip
        front = try c.decode(String.self, forKey: .front)
        back = try c.decode(String.self, forKey: .back)
        answer = try c.decodeIfPresent(Bool.self, forKey: .answer)
        source = try c.decodeIfPresent(CardSource.self, forKey: .source) ?? .manual
        materialId = try c.decodeIfPresent(UUID.self, forKey: .materialId)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        noteId = try c.decodeIfPresent(UUID.self, forKey: .noteId)
        noteSection = try c.decodeIfPresent(String.self, forKey: .noteSection)
        noteBlockId = try c.decodeIfPresent(String.self, forKey: .noteBlockId)
        noteBlockHash = try c.decodeIfPresent(String.self, forKey: .noteBlockHash)
    }
}

extension StudyCard {
    // 넘긴 결과다. 참·거짓 카드는 고른 답이 맞으면 앎이고 틀리면 모름이다. 답이 없는 카드에 고른 답은 맞힌 것이 아니다.
    public func knows(picking picked: Bool) -> Bool { answer == picked }

    // 앞뒤 공백만 다른 블록은 같은 블록이다. 편집기가 줄 끝 공백을 지우거나 블록 뒤에 빈 줄을 더해도 "원본 변경됨"이 뜨지 않게 한다.
    public static func blockHash(_ source: String) -> String { ContentHash.of(source.trimmingCharacters(in: .whitespacesAndNewlines)) }

    // 원본 블록을 찾지 못해도(블록을 지웠거나 블록 ID를 바꿨다) 바뀐 것이다. 노트 블록에서 만들지 않은 카드는 바뀌지 않는다.
    public func sourceChanged(block: String?) -> Bool {
        guard let noteBlockHash else { return false }
        return block.map { Self.blockHash($0) != noteBlockHash } ?? true
    }
}
