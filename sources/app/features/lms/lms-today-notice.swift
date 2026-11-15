import FolioDomain
import SwiftUI

// 오늘 화면에는 요약만 둔다. 같은 제안을 두 곳에서 따로 처리하지 않도록 처리는 LMS 탭에서 한다(#132).
struct LMSTodayNotice: View {
    @State private var model: LMSModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: LMSModel(workspace: workspace)) }

    var body: some View {
        let rows = model.todayRows
        if !rows.isEmpty {
            NoticeCard(title: String(localized: .lmsTodayTitle(model.board.count)), detail: model.earliestDue, systemImage: "tray") {
                Button(.lmsOpenTab) { openLink(.lms(nil)) }.buttonStyle(.prominent)
            } rows: {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    CardRow(last: i == rows.count - 1) {
                        Text(row.classroom.title).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(row.proposals.count)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }
}
