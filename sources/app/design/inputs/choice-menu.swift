import FolioDomain
import SwiftUI

struct ChoiceMenu<Value: Hashable>: View {
    struct Option: Hashable {
        let value: Value
        let label: String
    }

    @Binding var selection: Value
    let options: [Option]

    init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options.map { Option(value: $0.0, label: $0.1) }
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            ChipLabel(options.first { $0.value == selection }?.label ?? "")
        }
        .menuStyle(.button)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }
}
