import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

// 정리 노트에 절 둘을 두고 절마다 카드를 잇는다. 노트 옆 카드 칸은 절 순서대로 묶어 쌓고 자리에서 답한다.
@MainActor
struct NoteCardsModelTests {
    struct Made {
        let workspace: Workspace
        let note: UUID
        let unit: UUID
        let cards: [StudyCard]
    }

    func made() throws -> Made {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let body = "# 홀의 정리\n\n## 용어\n\n이웃 집합\n\n## 정리와 증명\n\n> [!theorem] Hall\n> 조건\n"
        let note = try #require(
            workspace.run(NoteAdd(course: graphTheory, title: "기말 02 홀의 정리", kind: .unit, body: body, units: [unit]))?.made)
        func card(_ front: String, _ section: String?, answer: Bool? = nil) -> StudyCard {
            var card = StudyCard(
                device: workspace.device, at: .now, unitId: unit, kind: answer == nil ? .flip : .trueFalse, front: front, back: "뒤",
                answer: answer)
            card.noteSection = section
            return card
        }
        let cards = [
            card("홀의 조건", "정리와 증명"), card("이웃 집합", "용어"), card("정규 이분 그래프에는 완전 매칭이 있다.", "정리와 증명", answer: true),
            card("없어진 절의 카드", "보기"),
        ]
        workspace.run(CardSave(course: graphTheory, cards: cards, note: note))
        return Made(workspace: workspace, note: note, unit: unit, cards: cards)
    }

    @Test func cardsAreGroupedBySectionAndTheFirstUnreadSectionIsInFocus() throws {
        let m = try made()
        let model = NoteCardsModel(workspace: m.workspace, courseId: graphTheory, noteId: m.note)
        let groups = model.groups
        #expect(model.exists && model.noteTitle == "기말 02 홀의 정리" && model.unit == m.unit)
        #expect(groups.map(\.title) == ["용어", "정리와 증명", "노트 전체"])
        #expect(groups.map { $0.cards.map(\.card.id) } == [[m.cards[1].id], [m.cards[0].id, m.cards[2].id], [m.cards[3].id]])
        #expect(model.subtitle(groups) == "이 절 0/1 · 노트 0/4" && model.note(groups[1]) == "0/2")
        #expect(model.focused(in: groups)?.section == "용어" && model.current(in: groups) == m.cards[1].id)
        #expect(model.link(to: groups[1]) == AppLink(.note, m.note, anchor: .heading("정리와 증명")))
        #expect(model.link(to: groups[2]) == AppLink(.note, m.note))

        // 절 묶음을 고르면 그 절이 "이 절"이고 키는 그 절의 첫 카드를 누른다.
        model.choose(groups[1])
        #expect(model.focused(in: groups)?.section == "정리와 증명" && model.current(in: groups) == m.cards[0].id)
        #expect(model.subtitle(groups) == "이 절 0/2 · 노트 0/4")
        // 새 카드는 보던 절에 잇는다.
        let draft = try #require(model.draft(in: groups))
        #expect(draft.noteId == m.note && draft.noteSection == "정리와 증명" && draft.unitId == m.unit && draft.source == .manual)
    }

    @Test func aFlipCardIsRevealedThenMarkedAndATrueFalseCardIsPicked() throws {
        let m = try made()
        let model = NoteCardsModel(workspace: m.workspace, courseId: graphTheory, noteId: m.note)
        let (flip, claim) = (m.cards[0], m.cards[2])

        // 뒤집기 전에는 앎과 모름을 고를 수 없다.
        model.mark(flip, known: true)
        #expect(model.face(of: flip) == .front)
        model.reveal(flip)
        #expect(model.face(of: flip) == .back && model.focused(in: model.groups)?.section == "정리와 증명")
        model.mark(flip, known: false)
        #expect(model.face(of: flip) == .answered(known: false, picked: nil))
        #expect(model.current(in: model.groups) == claim.id)

        #expect(model.verdict(claim) == nil)
        model.pick(claim, answer: false)
        #expect(model.face(of: claim) == .answered(known: false, picked: false) && model.verdict(claim)?.text == "틀림 · 답은 참")
        // 답한 카드는 다시 답하지 않는다.
        model.pick(claim, answer: true)
        #expect(model.face(of: claim) == .answered(known: false, picked: false))

        let groups = model.groups
        #expect(model.subtitle(groups) == "이 절 2/2 · 노트 2/4" && model.note(groups[1]) == "2/2")
        // 이 절을 다 답하면 키는 다음 절의 카드로 넘어간다.
        #expect(model.current(in: groups) == m.cards[3].id)
        let study = try #require(m.workspace.study(of: graphTheory))
        #expect(study.cards[flip.id]?.status.isOpen == true && study.cards[claim.id]?.status.isOpen == true)
        #expect(model.chip(try #require(study.cards[flip.id]))?.text == "모름")
    }

    @Test func renamingASectionMovesItsCardsToTheNote() throws {
        let m = try made()
        let model = NoteCardsModel(workspace: m.workspace, courseId: graphTheory, noteId: m.note)
        model.choose(model.groups[0])
        m.workspace.run(NoteWrite(course: graphTheory, note: "Notes/기말 02 홀의 정리.md", text: "# 홀의 정리\n\n## 정리와 증명\n"))
        model.load()
        let groups = model.groups
        #expect(groups.map(\.title) == ["정리와 증명", "노트 전체"])
        #expect(groups[1].cards.map(\.card.id) == [m.cards[1].id, m.cards[3].id])
        // 고른 절이 없어지면 넘기지 않은 첫 카드의 절로 돌아간다.
        #expect(model.focused(in: groups)?.section == "정리와 증명")
    }

    @Test func aNoteThatIsGoneHasNoScreen() throws {
        let workspace = try fixtureWorkspace()
        let model = NoteCardsModel(workspace: workspace, courseId: graphTheory, noteId: UUID())
        #expect(!model.exists && model.groups.isEmpty && model.current(in: []) == nil)
    }
}
