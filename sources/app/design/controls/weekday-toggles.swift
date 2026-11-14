import FolioDomain
import SwiftUI

struct WeekdayToggles: View {
    @Binding var selection: Set<Int>
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { if selection.count > 1 { selection.remove(day) } } else { selection.insert(day) }
                } label: {
                    Text(ClassTime.weekdayNames[day - 1])
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.Palette.onFill : Theme.Palette.textSecondary)
                        .frame(width: 28, height: 28)  // design: one-off, a one-letter day in a round toggle
                        .background(on ? accent.fill : Theme.Palette.fill, in: .circle)
                        .contentShape(TouchTarget())
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
