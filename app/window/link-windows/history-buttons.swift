import FolioDomain
import SwiftUI

struct HistoryButtons: View {
    let navigator: Navigator
    let title: (Navigator.Entry) -> String

    static let width = Theme.Size.toolbarButton * 2

    var body: some View {
        HStack(spacing: 0) {
            step(back: true)
            step(back: false)
        }
        .toolbarGroup()
        .buttonStyle(.toolbar)
        .menuStyle(.button)
    }

    func step(back: Bool) -> some View {
        let list = back ? navigator.backList : navigator.forwardList
        return Menu {
            ForEach(Array(list.enumerated()), id: \.offset) { i, entry in
                Button(title(entry)) { if back { navigator.back(i + 1) } else { navigator.forward(i + 1) } }
            }
        } label: {
            Label(back ? .navigationBack : .navigationForward, systemImage: back ? "chevron.backward" : "chevron.forward")
        } primaryAction: {
            if back { navigator.back() } else { navigator.forward() }
        }
        .menuIndicator(.hidden)
        .disabled(list.isEmpty)
        .help(Text(back ? .navigationBackHelp : .navigationForwardHelp))
    }
}
