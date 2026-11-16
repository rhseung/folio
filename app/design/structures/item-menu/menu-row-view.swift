import FolioDomain
import SwiftUI

struct MenuRowView: View {
    let row: MenuRow
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows

    var body: some View {
        switch row.kind {
        case .action(let action):
            Button(row.title, systemImage: row.symbol, role: row.role) { action() }.disabled(row.disabled)
        case .check(let on, let set):
            Toggle(isOn: Binding(get: { on }, set: { set($0) })) { Label(row.title, systemImage: row.symbol) }
                .disabled(row.disabled)
        case .submenu(let leaves):
            Menu {
                ForEach(leaves) { leaf in
                    if let checked = leaf.checked {
                        // iPad 메뉴도 Mac처럼 체크 표시를 그리도록 `Toggle`로 둔다.
                        Toggle(isOn: Binding(get: { checked }, set: { _ in leaf.action() })) { Label(leaf.title, systemImage: leaf.symbol) }
                    } else {
                        Button(leaf.title, systemImage: leaf.symbol) { leaf.action() }
                    }
                }
            } label: {
                Label(row.title, systemImage: row.symbol)
            }
            .disabled(row.disabled)
        case .share(let link, let course):
            ShareMenu(link: link, course: course)
        case .open(let link, let course, let action):
            Button(row.title, systemImage: row.symbol, role: row.role) { action() }.disabled(row.disabled)
            if let link {
                ForEach(LinkMenu.placements(multipleWindows: multipleWindows).filter { $0 == .tab || $0 == .beside }, id: \.self) {
                    placement in
                    Button(placement.title, systemImage: placement.symbol) { openLink(link, in: placement, course: course) }
                        .disabled(row.disabled)
                }
            }
        }
    }
}
