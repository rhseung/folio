import FolioCore
import FolioDomain
import Foundation

public struct CardDrafts: StructuredResult, Equatable {
    public struct Draft: Codable, Sendable, Equatable {
        public var front: String
        public var back: String
        public var page: Int?

        public init(front: String, back: String, page: Int? = nil) {
            self.front = front
            self.back = back
            self.page = page
        }

        public func card(unitId: UUID, materialId: UUID?, device: DeviceID, at date: Date) -> StudyCard {
            var card = StudyCard(device: device, at: date, unitId: unitId, front: front, back: back, source: .claude)
            card.materialId = materialId
            card.page = materialId == nil ? nil : page
            return card
        }
    }

    public var cards: [Draft]

    public static let schema = Schema.object([
        "cards": Schema.array(Schema.object(["front": Schema.string, "back": Schema.string, "page": Schema.nullable(Schema.integer)]))
    ])
}
