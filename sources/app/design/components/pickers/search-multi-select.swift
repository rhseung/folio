import FolioDomain
import SwiftUI

struct SearchMultiSelect<Value: Hashable>: View {
    @Binding var selection: [Value]
    let options: [PickOption<Value>]
    var placeholder = String(localized: .designPick)
    var summary: String?
    var subtree: ((Value) -> Set<Value>)?

    var body: some View {
        SearchPicker(
            options: options, isSelected: { selection.contains($0) },
            pick: { id in
                let group = subtree?(id) ?? [id]
                if selection.contains(id) {
                    selection.removeAll { group.contains($0) }
                } else {
                    selection += options.map(\.id).filter { group.contains($0) && !selection.contains($0) }
                }
            }, multiple: true
        ) {
            let titles = selection.compactMap { id in options.first { $0.id == id }?.title }
            ChipLabel(
                summary ?? titles.first.map { titles.count > 1 ? String(localized: .designPickedMany(titles.count, $0)) : $0 }
                    ?? placeholder)
        }
    }
}
