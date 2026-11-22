import FolioCore
import FolioDomain
import Foundation

struct CardDraft: Identifiable {
    var id = UUID()
    var original: StudyCard?
    var unitId: UUID
    var front = ""
    var back = ""

    init(unitId: UUID) {
        self.unitId = unitId
    }

    init(_ card: StudyCard) {
        original = card
        unitId = card.unitId
        front = card.front
        back = card.back
    }

    var isValid: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func card(device: DeviceID, at now: Date) -> StudyCard {
        var card = original ?? StudyCard(device: device, at: now, unitId: unitId, front: front, back: back)
        card.unitId = unitId
        card.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        card.touch(by: device, at: now)
        return card
    }
}
