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
            StatStrip(items: [
                .init(title: String(localized: .quizStatsAccuracy), value: stats.total.accuracyText),
                .init(title: String(localized: .quizStatsAttempted), value: "\(stats.total.attempted) / \(stats.total.items)"),
                .init(
                    title: String(localized: .quizStatsOpen), value: String(localized: .quizCardCount(stats.total.open)),
                    tone: stats.total.open > 0 ? .danger : .plain),
                .init(title: String(localized: .quizStatsResolved), value: String(localized: .quizCardCount(stats.total.resolved))),
                .init(title: String(localized: .quizStatsSolvedToday), value: "\(stats.solvedToday)"),
            ])

            Block(
                title: String(localized: .quizStatsWrongList),
                note: stats.due.isEmpty ? nil : String(localized: .quizCardCount(stats.due.count)),
                trailing: {
                    if !stats.due.isEmpty {
                        Button(.quizStatsSolveAllWrong) { solve(model.solveAllWrong(stats.units)) }
                            .buttonStyle(.ghost)
                    }
                }
            ) {
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
                            Button(.quizStatsSolveUnitWrong) { solve(model.solveWrong(of: card.unitId, units: stats.units)) }
                                .buttonStyle(.ghost)
                        }
                        .contextMenu {
                            CardMenu(courseId: course.id, card: card) { solve(model.solveWrong(of: card.unitId, units: stats.units)) }
                        }
                    }
                }
            }

            Block(String(localized: .quizByUnit)) {
                let shown = stats.shownUnits
                Card {
                    if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .quizStatsNoUnits)) } }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                        TallyRow(
                            title: unit.title, tally: stats.byUnit[unit.id]!, items: { .quizCardCount($0) }, last: i == shown.count - 1)
                    }
                }
            }

            if !stats.byCategory.isEmpty {
                Block(String(localized: .quizStatsByCategory)) {
                    let categories = stats.categories
                    Card {
                        ForEach(Array(categories.enumerated()), id: \.element) { i, c in
                            TallyRow(
                                title: c.label, tally: stats.byCategory[c]!, items: { .quizCardCount($0) }, last: i == categories.count - 1)
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
