import FolioDomain
import SwiftUI

struct SearchSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [PickOption<Value>]
    var placeholder = String(localized: .designPick)

    var body: some View {
        SearchPicker(options: options, isSelected: { $0 == selection }, pick: { selection = $0 }) {
            ChipLabel(options.first { $0.id == selection }?.title ?? placeholder)
        }
    }
}
