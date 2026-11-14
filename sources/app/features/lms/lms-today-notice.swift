import FolioDomain
import SwiftUI

struct LMSTodayNotice: View {
    @State private var model: ProposalsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        let sections = model.waiting
        if !sections.isEmpty {
            NoticeCard(title: String(localized: .lmsTodayTitle(model.total)), detail: model.earliestDue, systemImage: "tray") {
                Button(.lmsOpenProposals) { openLink(.place(.proposals)) }.buttonStyle(.prominent)
            } rows: {
                ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                    CardRow(last: i == sections.count - 1) {
                        Text(section.classroom.title).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(section.proposals.count)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }
}
