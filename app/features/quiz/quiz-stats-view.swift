import FolioDomain
import SwiftUI

struct QuizStatsView: View {
    let course: LoadedCourse
    let model: QuizModel
    let solve: (SolveRequest) -> Void

    var body: some View {
        let stats = model.stats(course)
        let today = model.workspace.today
        Page {
            PageHeader(title: String(localized: .quizStatsTitle), subtitle: String(localized: .quizStatsSubtitle))
            // No detail lines: one item with a second line sat its value higher than the rest of the strip.
            StatStrip(items: [
                .init(title: String(localized: .quizStatsAccuracy), value: stats.total.accuracyText),
                .init(title: String(localized: .quizStatsAttempted), value: "\(stats.total.attempted) / \(stats.total.items)"),
                .init(title: String(localized: .quizStatsOpen), value: String(localized: .quizCardCount(stats.total.open)), tone: stats.total.open > 0 ? .danger : .plain),
                .init(title: String(localized: .quizStatsResolved), value: String(localized: .quizCardCount(stats.total.resolved))),
                .init(title: String(localized: .quizStatsSolvedToday), value: "\(stats.solvedToday)"),
            ])

            Block(title: String(localized: .quizStatsWrongList), note: stats.due.isEmpty ? nil : String(localized: .quizCardCount(stats.due.count)), trailing: {
                if !stats.due.isEmpty {
                    Button(.quizStatsSolveAllWrong) { solve(model.solveAllWrong(stats.units)) }
                        .buttonStyle(.ghost)
                }
            }) {
                Card {
                    if stats.due.isEmpty { CardRow(last: true) { EmptyLine(model.dueEmpty) } }
                    ForEach(Array(stats.due.enumerated()), id: \.element.id) { i, card in
                        let chip = model.dueChip(card)
                        CardRow(last: i == stats.due.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(markdown(card.prompt)).lineLimit(2)
                                Text(model.dueDetail(card, units: stats.units))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            Chip(chip.text, tone: chip.tone)
                            Button(.quizStatsSolve) { solve(model.solveWrong(of: card.unitId, units: stats.units)) }
                                .buttonStyle(.ghost)
                        }
                        .contextMenu { Button(.quizStatsSolveUnitWrong) { solve(model.solveWrong(of: card.unitId, units: stats.units)) } }
                    }
                }
            }

            Block(String(localized: .quizByUnit)) {
                let shown = stats.shownUnits
                Card {
                    if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .quizStatsNoUnits)) } }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                        TallyRow(title: unit.title, tally: stats.byUnit[unit.id]!, items: { .quizCardCount($0) }, last: i == shown.count - 1)
                    }
                }
            }

            if !stats.byCategory.isEmpty {
                Block(String(localized: .quizStatsByCategory)) {
                    let categories = stats.categories
                    Card {
                        ForEach(Array(categories.enumerated()), id: \.element) { i, c in
                            TallyRow(title: c.label, tally: stats.byCategory[c]!, items: { .quizCardCount($0) }, last: i == categories.count - 1)
                        }
                    }
                }
            }

            Block(String(localized: .quizStatsDaily), note: String(localized: .quizStatsDailyNote)) {
                DailyBars(counts: model.dailyCounts(today: today), today: today)
            }
        }
    }
}

/// A group's tally in fixed columns, so figures line up down the card.
struct TallyRow: View {
    let title: String
    let tally: WrongTally
    /// "N장" for cards, "N문제" for problems.
    let items: (Int) -> LocalizedStringResource
    let last: Bool

    var body: some View {
        CardRow(last: last) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(items(tally.items)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 52, alignment: .trailing)
            Meter(value: tally.accuracy ?? 0).frame(width: 96)
            Text(tally.accuracyText).frame(width: 40, alignment: .trailing)
            Text(.quizOpenCount(tally.open)).foregroundStyle(tally.open > 0 ? Theme.Palette.danger : Theme.Palette.textTertiary).frame(width: 60, alignment: .trailing)
            Text(.quizResolvedCount(tally.resolved)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 60, alignment: .trailing)
        }
        .font(Theme.Typeface.body.monospacedDigit())
    }
}

struct DailyBars: View {
    @Environment(\.accent) private var accent
    let counts: [(day: LocalDate, count: Int)]
    let today: LocalDate

    var body: some View {
        let top = max(counts.map(\.count).max() ?? 0, 1)
        Card(padding: Theme.Space.l) {
            HStack(alignment: .bottom, spacing: Theme.Space.tight) {
                ForEach(counts, id: \.day) { day, n in
                    VStack(spacing: Theme.Space.xs) {
                        Text(n > 0 ? "\(n)" : "").font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
                        RoundedRectangle(cornerRadius: Theme.Radius.small)
                            .fill(n > 0 ? accent.color : Theme.Palette.fill)
                            .frame(height: max(4, 70 * CGFloat(n) / CGFloat(top)))
                        Text("\(day.day)").font(Theme.Typeface.label.weight(.regular))
                            .foregroundStyle(day == today ? accent.ink : Theme.Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
    }
}
