import FolioDomain
import SwiftUI

@MainActor func revealInFinder(_ url: URL) {
    #if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([url])
    #endif
}

struct ItemMenu<Source: ItemMenuSource>: View {
    let source: Source

    var body: some View {
        let rows = source.commands.map(source.row)
        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            if i > 0 && rows[i - 1].group.band != row.group.band { Divider() }
            MenuRowView(row: row)
        }
    }
}
