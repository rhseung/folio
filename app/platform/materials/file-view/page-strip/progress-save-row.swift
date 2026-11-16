import FolioDomain
import SwiftUI

struct ProgressSaveRow: View {
    @Bindable var model: PageStripModel
    let editing: StripSection?
    @Environment(\.accent) private var accent

    var body: some View {
        let today = model.onlyToday
        StripEditRow(
            kind: editing == nil ? .new : .held, range: model.selectionLabel, confirm: String(localized: .commonSave),
            canConfirm: model.canSave, refusal: model.refusal, cancel: { model.clear() }, commit: { model.commit() }
        ) {
            Group {
                if let editing {
                    Text(editing.title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.text)
                } else if let today {
                    Text(today.day).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                    Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                } else {
                    Text(.fileViewProgressNew).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                }
            }
            .fixedSize()
        } extra: {
            if editing == nil, today == nil { classMenu }
            if editing != nil { removeButton }
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            withAnimation(Theme.Motion.quick) { model.remove() }
        } label: {
            Label(String(localized: .fileViewProgressRemove), systemImage: "link.badge.minus")
                #if os(iOS)
            .frame(minHeight: Theme.Size.touchTarget)
            .contentShape(.rect)
                #endif
        }
        .buttonStyle(.ghost)
        .controlSize(.small)
        .disabled(!model.canRemove)
    }

    private var classMenu: some View {
        Button {
            model.choosing = true
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(model.chosenChoice?.day ?? String(localized: .fileViewProgressNoClass)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pointing(.bordered))
        .controlSize(.small)
        .disabled(model.choices.isEmpty)
        .popover(isPresented: $model.choosing, arrowEdge: .trailing) { ProgressClassPicker(model: model) }
    }
}
