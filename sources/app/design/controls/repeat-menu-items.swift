import FolioDomain
import SwiftUI

struct RepeatMenuItems: View {
    let selection: AssignmentRepeat?
    let custom: Bool
    let pick: (AssignmentRepeat?) -> Void
    let customize: () -> Void

    var body: some View {
        row(String(localized: .repeatPickerNone), on: selection == nil && !custom) { pick(nil) }
        ForEach(AssignmentRepeat.presets, id: \.self) { rule in
            row(rule.label, on: selection == rule && !custom) { pick(rule) }
        }
        Divider()
        row(String(localized: .repeatPickerCustom), on: custom, action: customize)
    }

    private func row(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if on { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}
