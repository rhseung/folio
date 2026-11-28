import FolioDomain
import SwiftUI

// 노트 옆 카드 칸에 쌓이는 카드 한 장이다. 자리에서 답한다. 앞뒤 카드는 뒤집은 뒤 모름과 앎을 고르고, 참거짓 카드는 참이나 거짓을
// 고르면 답과 이유가 보인다.
struct NoteCardTile: View {
    let model: NoteCardsModel
    let record: CourseStudy.CardRecord
    // 키는 지금 답할 카드 한 장의 단추에만 준다. 쌓인 카드가 모두 같은 키를 들으면 어느 카드가 답하는지 알 수 없다.
    let isCurrent: Bool

    var body: some View {
        let card = record.card
        let face = model.face(of: card)
        Card(padding: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    Caption(card.kind.label)
                    Spacer(minLength: Theme.Space.s)
                    if let chip = model.chip(record) { Badge(chip.text, tone: chip.tone) }
                    PageMenuButton { CardMenu(courseId: model.courseId, card: card) }
                }
                StudyText(text: card.front).frame(maxWidth: .infinity, alignment: .leading)
                if card.kind == .flip, face != .front {
                    Theme.Palette.lineSoft.frame(height: 1)
                    StudyText(text: card.back).foregroundStyle(Theme.Palette.textSecondary)
                }
                if let verdict = model.verdict(card) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(verdict.text).font(Theme.Typeface.bodyStrong).foregroundStyle(verdict.tone.foreground).lineLimit(1)
                        StudyText(text: card.back).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    Spacer(minLength: 0)
                    switch card.kind {
                    case .flip: flipAnswers(card, face)
                    case .trueFalse: trueFalseAnswers(card, face)
                    }
                }
            }
        }
        .contextMenu { CardMenu(courseId: model.courseId, card: card) }
    }

    @ViewBuilder func flipAnswers(_ card: StudyCard, _ face: NoteCardsModel.Face) -> some View {
        switch face {
        case .front:
            AnswerCapsule(title: String(localized: .noteCardsFlip), key: isCurrent ? .cardFlip : nil) { model.reveal(card) }
        case .back:
            AnswerCapsule(title: String(localized: .cardsUnknown), look: .no, key: isCurrent ? .cardUnknown : nil) {
                model.mark(card, known: false)
            }
            AnswerCapsule(title: String(localized: .cardsKnown), look: .yes, key: isCurrent ? .cardKnown : nil) {
                model.mark(card, known: true)
            }
        case .answered(let known, _):
            // 답한 뒤에는 고른 쪽만 색으로 남긴다.
            Group {
                AnswerCapsule(title: String(localized: .cardsUnknown), look: known ? .plain : .no) {}
                AnswerCapsule(title: String(localized: .cardsKnown), look: known ? .yes : .plain) {}
            }
            .disabled(true)
        }
    }

    @ViewBuilder func trueFalseAnswers(_ card: StudyCard, _ face: NoteCardsModel.Face) -> some View {
        if case .answered(_, let picked) = face {
            Group {
                option(true, card: card, picked: picked)
                option(false, card: card, picked: picked)
            }
            .disabled(true)
        } else {
            AnswerCapsule(title: String(localized: .solveTrue), key: isCurrent ? .solveTrue : nil) { model.pick(card, answer: true) }
            AnswerCapsule(title: String(localized: .solveFalse), key: isCurrent ? .solveFalse : nil) { model.pick(card, answer: false) }
        }
    }

    // 답은 초록 체크로, 틀리게 고른 쪽은 빨간 가위표로 보인다.
    func option(_ value: Bool, card: StudyCard, picked: Bool?) -> some View {
        let isAnswer = card.answer == value
        let look: AnswerCapsule.Look = isAnswer ? .yes : picked == value ? .no : .plain
        return AnswerCapsule(
            title: String(localized: value ? .solveTrue : .solveFalse),
            systemImage: isAnswer ? "checkmark" : picked == value ? "xmark" : nil, look: look
        ) {}
    }
}
