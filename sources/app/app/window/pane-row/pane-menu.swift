import FolioAI
import FolioDomain
import SwiftUI

struct PaneMenu: View {
    let panes: TabPanes
    let index: Int
    var newTab: ((Navigator, ColumnPrefs) -> Void)?

    var body: some View {
        if panes.folded.contains(index) {
            Button(.panesUnfold, systemImage: "arrow.left.and.line.vertical.and.arrow.right") { panes.press(index) }
        } else {
            Button(.panesCollapse, systemImage: "arrow.right.and.line.vertical.and.arrow.left") { panes.collapse(index) }
                .disabled(!panes.canCollapse(index))
        }
        Button(.panesClose, systemImage: "xmark") { panes.close(index) }
            .disabled(panes.count < 2)
        if let newTab {
            Button(.panesToTab, systemImage: "macwindow.badge.plus") {
                let navigator = panes.navigators[index]
                let columns = panes.columns[index]
                if panes.close(index) { newTab(navigator, columns) }
            }
            .disabled(panes.count < 2)
        }
        Divider()
        Button(.panesMoveLeft, systemImage: "arrow.left") { panes.swap(index, index - 1) }
            .disabled(index == 0)
        Button(.panesMoveRight, systemImage: "arrow.right") { panes.swap(index, index + 1) }
            .disabled(index + 1 >= panes.count)
    }
}
