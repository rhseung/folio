import FolioCore
import FolioDomain
import FolioMarkdown
import Foundation

struct CardDraft: Identifiable {
    var id = UUID()
    var original: StudyCard?
    var unitId: UUID
    var front = ""
    var back = ""
    // 노트 블록에서 만든 카드의 원본이다(`NoteBlockCard`). 원본 블록이 바뀌면 카드에 "원본 변경됨"을 보인다.
    var noteId: UUID?
    var noteBlockId: String?
    var noteBlockHash: String?

    init(unitId: UUID) {
        self.unitId = unitId
    }

    init(unitId: UUID, note: UUID, block: NoteBlockCard, blockId: String?, source: String?) {
        self.unitId = unitId
        front = block.front
        back = block.back
        noteId = note
        noteBlockId = blockId
        noteBlockHash = source.map(StudyCard.blockHash)
    }

    init(_ card: StudyCard) {
        original = card
        unitId = card.unitId
        front = card.front
        back = card.back
        noteId = card.noteId
        noteBlockId = card.noteBlockId
        noteBlockHash = card.noteBlockHash
    }

    var isValid: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func card(device: DeviceID, at now: Date) -> StudyCard {
        var card =
            original
            ?? StudyCard(device: device, at: now, unitId: unitId, front: front, back: back, source: noteId == nil ? .manual : .note)
        card.unitId = unitId
        card.noteId = noteId
        card.noteBlockId = noteBlockId
        card.noteBlockHash = noteBlockHash
        card.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        card.touch(by: device, at: now)
        return card
    }
}
