import FolioDomain
import SwiftUI

/// Which class a new range was: the classes held so far with no pages of this file yet, today's picked first.
struct ProgressClassPicker: View {
    @Bindable var model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.fileViewProgressPickClass).font(Theme.Typeface.sectionTitle)
                if let label = model.selectionLabel {
                    Text(label).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs)
            Divider().padding(.vertical, Theme.Space.xxs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.choices) { choice in row(choice) }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .overflowFade(.vertical)
        }
        .padding(Theme.Space.tight)
        .frame(width: 240)
    }

    private func row(_ choice: PageStripModel.Choice) -> some View {
        let picked = model.chosen == choice.id
        return Button {
            model.chosen = choice.id
            model.choosing = false
        } label: {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "checkmark").font(Theme.Glyph.small).opacity(picked ? 1 : 0)
                Text(choice.title).lineLimit(1)
                if choice.today {
                    Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(picked ? accent.ink : Theme.Palette.text)
            .padding(Theme.Inset.listRow)
            .background(picked ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }
}
