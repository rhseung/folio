import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ToggleMenu: View {
    let title: String
    let items: [(id: UUID, label: String, on: Bool)]
    let toggle: (UUID) -> Void

    var body: some View {
        CommandList(
            options: items.map { SelectOption(id: $0.id, label: $0.label) }, isSelected: { id in items.contains { $0.id == id && $0.on } },
            onSelect: toggle, multiple: true
        ) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "link")
                Text(title)
            }
            .font(Theme.Typeface.caption)
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Palette.fill, in: .capsule)
            .contentShape(.capsule)
        }
    }
}
