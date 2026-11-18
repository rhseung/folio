import FolioDomain
import SwiftUI

struct AssignmentStatusMenu: View {
    let status: AssignmentStatus
    var tint: Color?
    var size: CGFloat = 20
    let set: (AssignmentStatus) -> Void

    var body: some View {
        Menu {
            ForEach(AssignmentStatus.menuOrder, id: \.self) { s in
                Button {
                    set(s)
                } label: {
                    Label(s.label, systemImage: s == status ? "checkmark" : s.symbol)
                }
            }
        } label: {
            AssignmentStatusIcon(status: status, tint: tint, size: size)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: status)
                .contentShape(.rect)
        }
        .menuButton(indicator: .hidden)
        .fixedSize()
        .help(Text(.assignmentsStatusHelp(status.label)))
    }
}
