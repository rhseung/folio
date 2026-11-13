import SwiftUI

#if os(iOS)
/// A touch screen's visible way into picking a range, over the pages: a long press does the same, but nothing says so
/// there, and the Mac's ⇧-click has no finger to match. While it is on, a line says what the next tap does.
struct ProgressPickBar: View {
    let model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        let on = model.pickingShown
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Button { withAnimation(Theme.Motion.quick) { model.togglePicking() } } label: {
                Label(String(localized: .fileViewProgressPick), systemImage: "rectangle.stack.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s)
                    .background(on ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                    .contentShape(.rect)
            }
            .buttonStyle(.ghost)
            .tint(accent.ink)
            .accessibilityAddTraits(on ? .isSelected : [])
            if on {
                Text(model.selection == nil ? .fileViewProgressPickFirst : .fileViewProgressPickEnd)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Space.s)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.s)
    }
}
#endif
