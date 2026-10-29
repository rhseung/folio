import FolioDomain
import SwiftUI

struct QuizStatsView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let model: QuizModel
    let solve: (SolveRequest) -> Void

    var body: some View {
        let units = course.outline.map(\.unit)
        let title = { (id: UUID) in units.first { $0.id == id }?.title }
        let today = workspace.today
        let history = { (card: QuizCard) in model.history(of: card.id) }
        let total = QuizStats.total(model.cards, history: history)
        let byUnit = QuizStats.tally(model.cards, keys: { [$0.unitId] }, history: history)
        let byCategory = QuizStats.tally(model.cards, keys: { [$0.category] }, history: history)
        let due = model.cards.filter { WrongFlow.isDue(history($0), today: today) }
        let solvedToday = model.attempts.filter { $0.day == today }.count + model.problemAttempts.filter { $0.day == today }.count
        Page {
            PageHeader(title: "오답과 통계", subtitle: "판정을 바꾼 시도는 바꾼 판정으로 셉니다")
            // No detail lines: one item with a second line sat its value higher than the rest of the strip.
            StatStrip(items: [
                .init(title: "정답률", value: total.accuracyText),
                .init(title: "푼 카드", value: "\(total.attempted) / \(total.items)"),
                .init(title: "남은 오답", value: "\(total.open)장", tone: total.open > 0 ? .danger : .plain),
                .init(title: "해결", value: "\(total.resolved)장"),
                .init(title: "오늘 푼 문제", value: "\(solvedToday)"),
            ])

            Block(title: "오답 목록", note: due.isEmpty ? nil : "\(due.count)장", trailing: {
                if !due.isEmpty {
                    Button("오답 모두 풀기") { solve(SolveRequest(scope: QuizScope(unitIds: Set(units.map(\.id)), onlyWrong: true), label: "오답만")) }
                        .buttonStyle(.ghost)
                }
            }) {
                Card {
                    if due.isEmpty { CardRow(last: true) { EmptyLine(model.attempts.isEmpty ? "아직 푼 카드가 없습니다" : "남은 오답이 없습니다") } }
                    ForEach(Array(due.enumerated()), id: \.element.id) { i, card in
                        CardRow(last: i == due.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(markdown(card.prompt)).lineLimit(2)
                                Text([title(card.unitId), card.category.label].compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            switch WrongFlow.status(history(card)) {
                            case .open(let since): Chip("\(since.short)부터", tone: .danger)
                            default: Chip("다시 확인", tone: .warning)
                            }
                            Button("풀기") { solveWrong(of: card.unitId, title: title(card.unitId)) }
                                .buttonStyle(.ghost)
                        }
                        .contextMenu { Button("이 단원 오답 풀기") { solveWrong(of: card.unitId, title: title(card.unitId)) } }
                    }
                }
            }

            Block("단원별") {
                // Only units with cards: forty rows of zeros buried the few that mean something.
                let shown = units.filter { byUnit[$0.id] != nil }
                Card {
                    if shown.isEmpty { CardRow(last: true) { EmptyLine("카드가 있는 단원이 없습니다. 카드 화면에서 만드세요.") } }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                        TallyRow(title: unit.title, tally: byUnit[unit.id]!, unit: "장", last: i == shown.count - 1)
                    }
                }
            }

            if !byCategory.isEmpty {
                Block("유형별") {
                    let categories = CardCategory.allCases.filter { byCategory[$0] != nil }
                    Card {
                        ForEach(Array(categories.enumerated()), id: \.element) { i, c in
                            TallyRow(title: c.label, tally: byCategory[c]!, unit: "장", last: i == categories.count - 1)
                        }
                    }
                }
            }

            Block("날짜별 풀이 수", note: "최근 14일 · 문제 묶음 포함") { DailyBars(days: model.attempts.map(\.day) + model.problemAttempts.map(\.day), today: today) }
        }
    }
}

extension QuizStatsView {
    func solveWrong(of unit: UUID, title: String?) {
        solve(SolveRequest(scope: QuizScope(unitIds: [unit], onlyWrong: true), label: "오답 · \(title ?? "")"))
    }
}

/// A group's tally in fixed columns, so figures line up down the card.
struct TallyRow: View {
    let title: String
    let tally: WrongTally
    /// `장` for cards, `문제` for problems.
    let unit: String
    let last: Bool

    var body: some View {
        CardRow(last: last) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(tally.items)\(unit)").foregroundStyle(Theme.Palette.textTertiary).frame(width: 52, alignment: .trailing)
            Meter(value: tally.accuracy ?? 0).frame(width: 96)
            Text(tally.accuracyText).frame(width: 40, alignment: .trailing)
            Text("오답 \(tally.open)").foregroundStyle(tally.open > 0 ? Theme.Palette.danger : Theme.Palette.textTertiary).frame(width: 60, alignment: .trailing)
            Text("해결 \(tally.resolved)").foregroundStyle(Theme.Palette.textTertiary).frame(width: 60, alignment: .trailing)
        }
        .font(Theme.Typeface.body.monospacedDigit())
    }
}

struct DailyBars: View {
    @Environment(\.accent) private var accent
    let days: [LocalDate]
    let today: LocalDate

    var body: some View {
        let counts = Dictionary(days.map { ($0, 1) }, uniquingKeysWith: +)
        let range = (0..<14).reversed().map { today.adding(days: -$0) }
        let top = max(range.map { counts[$0] ?? 0 }.max() ?? 0, 1)
        Card(padding: Theme.Space.l) {
            HStack(alignment: .bottom, spacing: Theme.Space.tight) {
                ForEach(range, id: \.self) { day in
                    let n = counts[day] ?? 0
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
