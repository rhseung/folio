import FolioDomain
import SwiftUI

struct Combobox<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    var prompt = String(localized: .designPick)

    var body: some View {
        CommandList(options: options, isSelected: { $0 == selection }, onSelect: { selection = $0 }) {
            SelectTrigger(options.first { $0.id == selection }?.label ?? prompt)
        }
    }
}
