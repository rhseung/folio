import FolioCore
import FolioDomain
import FolioMarkdown
import Foundation

struct CardDraft: Identifiable {
    var id = UUID()
    var original: StudyCard?
    var unitId: UUID
    var kind = CardKind.flip
    // 참거짓 카드는 앞이 문장이고 뒤가 이유다.
    var front = ""
    var back = ""
    var answer = true
    var source = CardSource.manual
    var noteId: UUID?
    var noteSection: String?
    // 노트 블록에서 만든 카드의 원본이다(`NoteBlockCard`). 원본 블록이 바뀌면 카드에 "원본 변경됨"을 보인다.
    var noteBlockId: String?
    var noteBlockHash: String?

    init(unitId: UUID) {
        self.unitId = unitId
    }

    // 노트 옆 카드 칸에서 더하는 카드는 그 노트와 보던 절에 잇는다.
    init(unitId: UUID, note: UUID, section: String?) {
        self.unitId = unitId
        noteId = note
        noteSection = section
    }

    init(unitId: UUID, note: UUID, block: NoteBlockCard, blockId: String?, source: String?) {
        self.unitId = unitId
        front = block.front
        back = block.back
        self.source = .note
        noteId = note
        noteBlockId = blockId
        noteBlockHash = source.map(StudyCard.blockHash)
    }

    init(_ card: StudyCard) {
        original = card
        unitId = card.unitId
        kind = card.kind
        front = card.front
        back = card.back
        answer = card.answer ?? true
        source = card.source
        noteId = card.noteId
        noteSection = card.noteSection
        noteBlockId = card.noteBlockId
        noteBlockHash = card.noteBlockHash
    }

    var isValid: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func card(device: DeviceID, at now: Date) -> StudyCard {
        var card = original ?? StudyCard(device: device, at: now, unitId: unitId, front: front, back: back, source: source)
        card.unitId = unitId
        card.kind = kind
        card.answer = kind == .trueFalse ? answer : nil
        card.noteId = noteId
        card.noteSection = noteId == nil ? nil : noteSection
        card.noteBlockId = noteBlockId
        card.noteBlockHash = noteBlockHash
        card.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        card.touch(by: device, at: now)
        return card
    }
}
