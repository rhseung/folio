import FolioCore
import FolioDomain
import Foundation
import Testing

struct NoteDeckTests {
    @Test func cardsStackInSectionOrderAndLostSectionsFallToTheNote() {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let proof = course.card("홀의 조건", note: hall, section: "정리와 증명")
        let term = course.card("이웃 집합", note: hall, section: "용어")
        let renamed = course.card("옛 절의 카드", note: hall, section: "보기")
        let loose = course.card("노트의 카드", note: hall)
        let claim = course.card("정규 이분 그래프에는 완전 매칭이 있다.", note: hall, section: "정리와 증명", answer: true)
        course.card("다른 노트", note: course.noteId("기말 10 증가 경로"), section: "용어")

        let deck = course.study(now: PlanCourse.at(12, 8)).noteDeck(hall, sections: ["홀의 정리", "용어", "정리와 증명", "용어"])
        // 카드가 없는 절은 묶음이 되지 않는다. 같은 이름의 절이 둘이면 앞의 것이다.
        #expect(deck.groups.map(\.section) == ["용어", "정리와 증명", nil])
        #expect(deck.groups.map { $0.cards.map(\.card.id) } == [[term.id], [proof.id, claim.id], [renamed.id, loose.id]])
        #expect(deck.progress == PlanProgress(done: 0, total: 5))
    }

    @Test func aDeckCountsWhatThePlanCounts() throws {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let cards = [
            course.card("a", note: hall, section: "용어"), course.card("b", note: hall, section: "용어"), course.card("c", note: hall),
        ]
        func flips(_ list: [(Int, Date)]) -> StudyLog {
            StudyLog(flips: list.map { (at: $0.1, event: CardFlipEvent(cardId: cards[$0.0].id, known: true)) })
        }
        let log = flips([(0, PlanCourse.at(12, 7, 20)), (1, PlanCourse.at(12, 8, 10)), (2, PlanCourse.at(12, 8, 11))])

        // 계획에 없는 노트는 넘긴 적이 있는 카드를 모두 센다.
        let free = course.study(now: PlanCourse.at(12, 8, 12), log: log)
        #expect(free.readExam(ofNote: hall) == nil && free.noteDeck(hall, sections: ["용어"]).progress.done == 3)

        let placed = try #require(
            course.study(now: PlanCourse.at(12, 8)).place(course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        course.exam.plan = placed.plan
        course.exam.planPeriod = placed.period
        let study = course.study(now: PlanCourse.at(12, 8, 12), log: log)
        let read = try #require(course.exam.plan.first { $0.target == .note(hall, .read) })
        let deck = study.noteDeck(hall, sections: ["용어"])
        #expect(study.readExam(ofNote: hall)?.readStart == PlanCourse.day(12, 8))
        #expect(deck.groups.map(\.progress) == [PlanProgress(done: 1, total: 2), PlanProgress(done: 1, total: 1)])
        #expect(deck.progress == study.progress(of: read))
    }

    @Test func aTrueFalseCardIsKnownWhenThePickMatchesItsAnswer() {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let claim = course.card("모든 이분 그래프에는 완전 매칭이 있다.", note: hall, answer: false)
        let flip = course.card("홀의 조건", note: hall)
        #expect(claim.kind == .trueFalse && claim.knows(picking: false) && !claim.knows(picking: true))
        #expect(flip.kind == .flip && flip.answer == nil && !flip.knows(picking: true))
    }

    @Test func cardsWrittenBeforeKindsAreFlipCards() throws {
        let unit = UUID()
        let old = #"{"unitId":"\#(unit.uuidString)","front":"매칭","back":"공통 끝점이 없는 변의 집합"}"#
        let card = try JSONDecoder().decode(StudyCard.self, from: Data(old.utf8))
        #expect(card.kind == .flip && card.answer == nil && card.noteSection == nil)

        var asked = StudyCard(device: UUID(), at: .distantPast, unitId: unit, kind: .trueFalse, front: "문장", back: "이유", answer: false)
        asked.noteId = UUID()
        asked.noteSection = "정리와 증명"
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(asked)) as? [String: Any])
        #expect(json["kind"] as? String == "true_false" && json["answer"] as? Bool == false)
        #expect(json["noteSection"] as? String == "정리와 증명")
        #expect(try JSONDecoder().decode(StudyCard.self, from: JSONEncoder().encode(asked)) == asked)
        // 앞뒤 카드는 답을 가지지 않는다.
        #expect(StudyCard(device: UUID(), at: .distantPast, unitId: unit, front: "a", back: "b", answer: true).answer == nil)
    }
}
