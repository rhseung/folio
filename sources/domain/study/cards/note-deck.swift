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

extension Exam {
    // 정독의 진행을 세기 시작하는 공부일이다. 지난 시험 때 넘긴 카드를 이 시험의 정독으로 세지 않도록 공부 기간이 시작한 날부터 센다.
    // 계획의 칩과 노트 옆 카드 칸이 이 값 하나로 센다. 기간이 없으면 넘긴 적이 있는 카드를 모두 센다.
    public var readStart: LocalDate? { planPeriod?.start }
}

extension CourseStudy {
    public func cards(ofNote note: UUID) -> [CardRecord] { allCards.filter { $0.card.noteId == note } }

    // 카드 칸이 따르는 시험이다. 정독의 진행은 시험마다 그 시험의 기간부터 세는데, 칸은 노트만 알고 시험을 모른다.
    // 이 노트의 정독을 놓은 시험이 여럿이면 이미 시작한 기간 가운데 가장 늦게 시작한 시험을 따른다. 아직 시작하지 않은 기간을 따르면
    // 지금 넘긴 카드가 계획의 칩에서는 세어지고 칸에서는 세어지지 않는다. 시작한 기간이 없으면 가장 먼저 시작할 시험이고,
    // 계획에 없는 노트는 nil이다.
    public func readExam(ofNote note: UUID) -> Exam? {
        let exams = file.exams.filter { exam in exam.plan.contains { !$0.isRemoved && $0.target == .note(note, .read) } }
        // 기간이 없는 시험은 처음부터 세므로 가장 일찍 시작한 것으로 본다.
        func startsEarlier(_ a: Exam, _ b: Exam) -> Bool {
            guard let b = b.readStart else { return false }
            return a.readStart.map { $0 < b } ?? true
        }
        return exams.filter { $0.readStart.map { $0 <= today } ?? true }.max(by: startsEarlier) ?? exams.min(by: startsEarlier)
    }

    // `sections`는 노트의 절을 본문 순서대로 적은 것이다(`NoteOutline`의 anchor). 노트 파일을 읽어야 알 수 있어서 부르는 쪽이
    // 넘긴다. 카드가 있는 절만 묶음이 되고, 절을 찾지 못한 카드는 맨 뒤의 묶음에 모인다.
    public func noteDeck(_ note: UUID, sections: [String]) -> NoteDeck {
        let since = readExam(ofNote: note)?.readStart
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
