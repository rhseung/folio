import FolioDomain
import SwiftUI

struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Chip(title, tone: isOn ? .success : .plain)
        }
        .buttonStyle(.pointing(.plain))
        .opacity(isOn ? 1 : 0.6)
    }
}
