import FolioDomain
import SwiftUI

struct ProblemCell: View {
    @Environment(\.accent) private var accent
    let set: ProblemSet
    let problem: ProblemSet.Problem
    let history: AttemptHistory
    let units: [FolioDomain.Unit]
    let linked: String
    let historyLine: String
    let openSheet: (() -> Void)?
    let mark: (Verdict) -> Void
    let toggleUnit: (UUID) -> Void
    @State private var open = false

    var body: some View {
        let status = WrongFlow.status(history)
        let (fill, ink): (Color, Color) =
            switch status {
            case .open: (Theme.Palette.dangerFill, Theme.Palette.danger)
            case .resolved: (accent.tint, accent.ink)
            case .neverWrong:
                history.isEmpty
                    ? (Theme.Palette.fill, Theme.Palette.textSecondary)
                    : (Theme.Palette.success.opacity(Theme.Opacity.tint), Theme.Palette.success)
            }
        let correct = WrongFlow.isOpen(status) ? String(localized: .quizProblemsResolve) : Verdict.correct.label
        Button {
            open = true
        } label: {
            VStack(spacing: Theme.Space.xxs) {
                Text(problem.number).font(Theme.Typeface.bodyStrong).monospacedDigit()
                if case .resolved = status { Image(systemName: "checkmark").font(Theme.Glyph.tiny) }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(linked)
        .contextMenu {
            ItemMenu(
                source: ProblemMenuSource(
                    problem: problem, units: units, correct: correct, openSheet: openSheet, mark: mark, toggleUnit: toggleUnit))
        }
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(.quizProblemsCellTitle(set.title, problem.number)).font(Theme.Typeface.bodyStrong)
                HStack(spacing: Theme.Space.s) {
                    Button(correct) {
                        mark(.correct); open = false
                    }
                    Button(Verdict.partial.label) {
                        mark(.partial); open = false
                    }
                    Button(Verdict.wrong.label) {
                        mark(.wrong); open = false
                    }
                }
                if !history.isEmpty {
                    Text(historyLine)
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Space.l)
        }
    }
}
