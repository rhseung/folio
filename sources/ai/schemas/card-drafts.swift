import FolioCore
import FolioDomain
import Foundation

public struct CardDrafts: StructuredResult, Equatable {
    public struct Draft: Codable, Sendable, Equatable {
        public var kind: CardKind
        public var front: String
        public var back: String
        public var answer: Bool?
        public var section: String?
        public var page: Int?

        public init(kind: CardKind = .flip, front: String, back: String, answer: Bool? = nil, section: String? = nil, page: Int? = nil) {
            self.kind = kind
            self.front = front
            self.back = back
            self.answer = answer
            self.section = section
            self.page = page
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(CardKind.self, forKey: .kind) ?? .flip
            front = try c.decode(String.self, forKey: .front)
            back = try c.decode(String.self, forKey: .back)
            answer = try c.decodeIfPresent(Bool.self, forKey: .answer)
            section = try c.decodeIfPresent(String.self, forKey: .section)
            page = try c.decodeIfPresent(Int.self, forKey: .page)
        }

        // 답이 없는 참거짓 카드나 빈 면이 있는 카드는 저장할 수 없어 카드가 되지 않는다. 노트의 절은 그 노트에 있는 제목일 때만 잇고,
        // 쪽은 출처 파일이 하나로 정해졌을 때만 남긴다.
        public func card(
            unitId: UUID, noteId: UUID? = nil, sections: [String] = [], materialId: UUID? = nil, device: DeviceID, at date: Date
        ) -> StudyCard? {
            let (front, back) = (
                front.trimmingCharacters(in: .whitespacesAndNewlines), back.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !front.isEmpty, !back.isEmpty, kind == .flip || answer != nil else { return nil }
            var card = StudyCard(
                device: device, at: date, unitId: unitId, kind: kind, front: front, back: back, answer: answer, source: .claude)
            card.noteId = noteId
            let written = section?.trimmingCharacters(in: .whitespaces)
            card.noteSection = noteId == nil ? nil : sections.first { $0 == written }
            card.materialId = materialId
            card.page = materialId == nil ? nil : page
            return card
        }
    }

    public var cards: [Draft]

    public static let schema = Schema.object([
        "cards": Schema.array(
            Schema.object([
                "kind": Schema.enumeration(CardKind.allCases.map(\.rawValue)), "front": Schema.string, "back": Schema.string,
                "answer": Schema.nullable(Schema.boolean), "section": Schema.nullable(Schema.string),
                "page": Schema.nullable(Schema.integer),
            ]))
    ])
}
