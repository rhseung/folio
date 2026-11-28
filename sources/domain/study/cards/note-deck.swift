import FolioCore
import Foundation

// 정리 노트 하나의 카드를 절 순서대로 묶은 값이다. 노트 옆 카드 칸이 그리고, 정독의 진행이 같은 카드를 센다.
public struct NoteDeck: Sendable, Equatable {
    public struct Group: Sendable, Equatable, Identifiable {
        // 노트의 절(`StudyCard.noteSection`)이다. nil은 절에 잇지 않았거나 절을 찾지 못한 카드의 묶음이다.
        public var section: String?
        public var cards: [CourseStudy.CardRecord]
        public var read: Int
        public var id: String { section ?? "" }

        public var progress: PlanProgress { PlanProgress(done: read, total: cards.count) }
    }

    public var groups: [Group]

    public var cards: [CourseStudy.CardRecord] { groups.flatMap(\.cards) }
    public var progress: PlanProgress {
        PlanProgress(done: groups.reduce(0) { $0 + $1.read }, total: groups.reduce(0) { $0 + $1.cards.count })
    }
}

extension CourseStudy.CardRecord {
    // 공부일 `day`부터 한 번이라도 넘긴 카드다. `day`가 없으면 넘긴 적이 있는 카드다.
    public func isRead(since day: LocalDate?) -> Bool { flips.contains { flip in day.map { flip.day >= $0 } ?? true } }
}

extension CourseStudy {
    public func cards(ofNote note: UUID) -> [CardRecord] { allCards.filter { $0.card.noteId == note } }

    // 정독의 진행을 세기 시작하는 공부일이다. 이 노트의 정독을 놓은 시험의 공부 기간 시작일이고, 그런 시험이 여럿이면 가장 늦게
    // 시작하는 기간이다. 지난 시험 때 넘긴 카드를 다음 시험의 정독으로 세지 않기 위해서다. 계획에 없는 노트는 nil이다.
    public func readStart(ofNote note: UUID) -> LocalDate? {
        file.exams.filter { exam in exam.plan.contains { !$0.isRemoved && $0.target == .note(note, .read) } }
            .compactMap(\.planPeriod?.start).max()
    }

    // `sections`는 노트의 절을 본문 순서대로 적은 것이다(`NoteOutline`의 anchor). 노트 파일을 읽어야 알 수 있어서 부르는 쪽이
    // 넘긴다. 카드가 있는 절만 묶음이 되고, 절을 찾지 못한 카드는 맨 뒤의 묶음에 모인다.
    public func noteDeck(_ note: UUID, sections: [String]) -> NoteDeck {
        let since = readStart(ofNote: note)
        let known = Set(sections)
        var bySection: [String?: [CardRecord]] = [:]
        for record in cards(ofNote: note) {
            let section = record.card.noteSection.flatMap { known.contains($0) ? $0 : nil }
            bySection[section, default: []].append(record)
        }
        var seen = Set<String>()
        let order: [String?] = sections.filter { seen.insert($0).inserted } + [nil]
        return NoteDeck(
            groups: order.compactMap { section in
                guard let cards = bySection[section] else { return nil }
                return NoteDeck.Group(section: section, cards: cards, read: cards.count { $0.isRead(since: since) })
            })
    }
}
