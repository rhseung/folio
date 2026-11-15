import FolioDomain
import SwiftUI

struct ItemButton<Source: ItemMenuSource>: View {
    let source: Source
    let command: Source.Command

    var body: some View {
        if source.commands.contains(command) {
            let row = source.row(command)
            switch row.kind {
            case .action(let action):
                Button(row.title, systemImage: row.symbol, role: row.role) { action() }.disabled(row.disabled)
            case .check(let on, let set):
                Button(row.title) { set(!on) }.disabled(row.disabled)
            case .submenu, .share:
                EmptyView()
            }
        }
    }
}
