import FolioDomain
import SwiftUI

struct CardFlipSheet: View {
    @State private var model: CardFlipModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, course: UUID, unit: UUID?, scope: [UUID]? = nil) {
        _model = State(initialValue: CardFlipModel(workspace: workspace, courseId: course, unitId: unit, scope: scope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Text(model.title).font(Theme.Typeface.columnTitle).lineLimit(1)
                Spacer(minLength: Theme.Space.m)
                if !model.isDone, !model.deck.isEmpty {
                    Text(model.progress).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                }
                Button(.commonClose) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let card = model.current {
                face(card)
                answers
            } else if model.isDone {
                done
            } else {
                EmptyLine(String(localized: .cardsFlipEmpty))
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Size.solveSetup)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
    }

    // 앞면을 누르면 뒤집는다. 스페이스 키도 같다.
    func face(_ card: StudyCard) -> some View {
        Button {
            model.flip()
        } label: {
            VStack(spacing: Theme.Space.m) {
                Caption(String(localized: model.flipped ? .cardsBack : .cardsFront))
                StudyText(text: model.flipped ? card.back : card.front)
                    .font(model.flipped ? Theme.Typeface.body : Theme.Typeface.figureMedium)
                    .multilineTextAlignment(.center)
                if !model.flipped {
                    Text(.cardsFlipHint).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.flipCardMin)
            .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .shortcut(.cardFlip)
    }

    // 뒤집기 전에는 앎과 모름을 고르지 않는다. 답을 떠올려 본 뒤에 고르게 하기 위해서다.
    var answers: some View {
        HStack(spacing: Theme.Space.m) {
            big(String(localized: .cardsUnknown), tone: .danger, key: .cardUnknown) { model.mark(known: false) }
            big(String(localized: .cardsKnown), tone: .success, key: .cardKnown) { model.mark(known: true) }
        }
        .disabled(!model.flipped)
        .opacity(model.flipped ? 1 : Theme.Opacity.disabled)
    }

    func big(_ title: String, tone: Tone, key: ShortcutID, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.Typeface.figureMedium)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.bigButton)
                .background(tone.fill, in: .rect(cornerRadius: Theme.Radius.control))
                .foregroundStyle(tone.foreground)
                .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .shortcut(key)
    }

    var done: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(model.resultLine).font(Theme.Typeface.figureMedium).monospacedDigit()
            HStack {
                Spacer()
                if !model.unknown.isEmpty { Button(.cardsFlipAgain) { model.againUnknown() } }
                Button(.commonDone) { dismiss() }.buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}
