import FolioDomain
import SwiftUI

struct SolveResult: View {
    @Bindable var model: SolveModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLink) private var openLink

    var body: some View {
        let units = model.unitResults()
        let reasons = model.reasonSummary
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.solveResultTitle).font(Theme.Typeface.columnTitle)
                Text(model.resultLine).font(Theme.Typeface.figureMedium).monospacedDigit()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if !units.isEmpty {
                        Block(String(localized: .solveResultUnits)) {
                            Card {
                                ForEach(Array(units.enumerated()), id: \.element.unit.id) { i, row in
                                    CardRow(last: i == units.count - 1) {
                                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                            StudyText(text: row.unit.title, look: .title).lineLimit(1)
                                            Text(row.line).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        }
                                        Spacer(minLength: Theme.Space.m)
                                        ReadinessBadge(readiness: row.readiness)
                                    }
                                }
                            }
                        }
                    }
                    if !reasons.isEmpty {
                        Block(String(localized: .solveResultReasons)) {
                            Card {
                                ForEach(Array(reasons.enumerated()), id: \.element.reason) { i, row in
                                    CardRow(last: i == reasons.count - 1) {
                                        Text(row.reason.label)
                                        Spacer(minLength: Theme.Space.m)
                                        Text(verbatim: "\(row.count)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: Theme.Space.s) {
                Button(.solvePlan) {
                    dismiss()
                    openLink(.course(model.request.course, page: .units), course: model.request.course)
                }
                Spacer()
                if model.wrongCount > 0 { Button(.solveRetryWrong) { model.retryWrong() } }
                Button(.commonDone) { dismiss() }.buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(Theme.Space.xl)
        .frame(width: Theme.Size.solveSetup)
        .frame(minHeight: Theme.Size.emptyWindow.height)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
    }
}
