import FolioDomain
import SwiftUI

// 시험 하나의 공부 기간이다. 시작일과 끝낼 날을 고르면 앱이 그 안에 정리 노트를 다시 놓는다.
struct PlanPeriodRow: View {
    let model: PlanModel
    let period: PlanModel.Period
    var last = false

    var body: some View {
        CardRow(last: last) {
            FoldingRow {
                Text(period.title).lineLimit(1)
            } control: {
                // 좁은 칸에서는 기간 뒤 고르기가 날짜 아래로 내려간다. 날짜 둘은 한 쌍이라 함께 둔다.
                FlowLayout(spacing: Theme.Space.m, centered: true) {
                    HStack(spacing: Theme.Space.s) {
                        DateChip(
                            selection: Binding(get: { period.start }, set: { model.setStart($0, of: period) }), showsTime: false,
                            showsYear: false
                        )
                        .fixedSize()
                        Text(verbatim: "–").foregroundStyle(Theme.Palette.textTertiary)
                        DateChip(
                            selection: Binding(get: { period.end }, set: { model.setEnd($0, of: period) }), showsTime: false,
                            showsYear: false
                        )
                        .fixedSize()
                    }
                    SegmentedControl(
                        selection: Binding(get: { period.period.after }, set: { model.setAfter($0, of: period) }),
                        options: model.afterOptions, size: .small
                    )
                    .fixedSize()
                    .help(Text(.planAfterHelp))
                }
                .layoutPriority(1)
            }
        }
    }
}
