import FolioDomain
import SwiftUI

// 계획 블록이다. 기간, 오늘의 줄, 다음 날들의 카드 순서로 쌓는다. 오늘 화면에서는 오늘의 줄만 보인다.
struct PlanBlock: View {
    @State private var model: PlanModel

    init(workspace: Workspace, scope: PlanModel.Scope) {
        _model = State(initialValue: PlanModel(workspace: workspace, scope: scope))
    }

    var body: some View {
        let board = model.board
        let periods = model.periods
        // 그릴 것이 없으면 자리도 차지하지 않는다. 빈 묶음도 페이지의 블록 간격을 한 번 더 받기 때문이다.
        if model.shows(board, periods) {
            VStack(alignment: .leading, spacing: model.fillsPage ? Theme.Space.section : Theme.Space.l) {
                blocks(board, periods)
            }
            .confirming($model.pending)
        }
    }

    @ViewBuilder func blocks(_ board: PlanBoard, _ periods: [PlanModel.Period]) -> some View {
        Group {
            if !periods.isEmpty {
                Block(String(localized: .planTitle), note: model.periodNote(periods)) {
                    Card {
                        ForEach(Array(periods.enumerated()), id: \.element.id) { i, period in
                            PlanPeriodRow(model: model, period: period, last: i == periods.count - 1)
                        }
                    }
                }
            }
            if !board.today.isEmpty {
                Block(String(localized: model.showsNext ? .planToday : .planTitle), note: model.todayNote(board)) {
                    Card {
                        ForEach(Array(board.today.enumerated()), id: \.element.id) { i, row in
                            PlanRowView(model: model, row: row, last: i == board.today.count - 1)
                        }
                    }
                }
            }
            if model.showsNext, !board.next.isEmpty { next(board) }
            if model.addsTasks { addRow }
        }
    }

    func next(_ board: PlanBoard) -> some View {
        let days = model.days(board)
        return Block(title: String(localized: .planNext), note: model.nextNote(board)) {
            if days.folded > 0 {
                Button(model.showsAll ? .commonCollapse : .planMore) { withAnimation(.snappy) { model.showsAll.toggle() } }
                    .buttonStyle(.ghost)
            }
        } content: {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.Size.planDayCard), spacing: Theme.Space.m, alignment: .top)],
                alignment: .leading,
                spacing: Theme.Space.m
            ) {
                ForEach(days.shown) { day in PlanDayCard(model: model, day: day) }
            }
        }
    }

    // 좁은 칸에서 한 줄에 두면 날짜 칩이 눌려 날짜가 여러 줄로 꺾인다. 그래서 이름 아래로 접는다.
    var addRow: some View {
        Card {
            CardRow(last: true) {
                FoldingRow {
                    Text(.planAddTask).lineLimit(1)
                } control: {
                    InlineField(String(localized: .planAddPrompt), text: $model.newTitle).onSubmit(model.add)
                    DateChip(selection: $model.newDay, showsTime: false, showsYear: false).fixedSize()
                    Button(.commonAdd, action: model.add).buttonStyle(.ghost).disabled(!model.canAdd)
                }
            }
        }
    }
}
