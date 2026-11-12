import SwiftUI

/// The edit row's dot, under where the headers' chevrons stand: filled for pages held, open for pages a save will
/// give, grey and open for pages that go to nothing.
struct StripDot: View {
    let kind: StripSection.Kind
    @Environment(\.accent) private var accent

    var body: some View {
        switch kind {
        case .held: CourseDot(color: accent.color)
        case .new: Circle().strokeBorder(accent.color, lineWidth: 2).frame(width: Theme.Size.dot, height: Theme.Size.dot)
        case .none: Circle().strokeBorder(Theme.Palette.textTertiary, lineWidth: 2).frame(width: Theme.Size.dot, height: Theme.Size.dot)
        }
    }
}

/// The row a range is changed or saved from, in place of a section's header or at a new range's end: its dot and what
/// it is, the range on a line of its own (the column is too narrow for "11/4(수) 오늘 19–21쪽" on one), whatever
/// else it asks, [취소][confirm]. Tinted and ringed in the course's colour: the tint alone read as one more section
/// beside a section's own.
struct StripEditRow<Title: View, Extra: View>: View {
    let kind: StripSection.Kind
    let range: String?
    let confirm: String
    let canConfirm: Bool
    var refusal: String?
    let cancel: () -> Void
    let commit: () -> Void
    @ViewBuilder var title: Title
    @ViewBuilder var extra: Extra
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.tight) {
                    StripDot(kind: kind)
                    title.lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                if let range {
                    Text(range).font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit().foregroundStyle(accent.ink)
                        .padding(.leading, Theme.Size.dot + Theme.Space.tight)
                }
            }
            extra
            HStack(spacing: Theme.Space.tight) {
                Button { withAnimation(Theme.Motion.quick) { cancel() } } label: {
                    Text(.commonCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghost)
                Button { withAnimation(Theme.Motion.quick) { commit() } } label: {
                    Text(confirm).frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .disabled(!canConfirm)
            }
            .controlSize(.small)
            if let refusal {
                Text(refusal).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Its dot under the headers' chevrons.
        .padding(Theme.Space.s)
        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.strip))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.strip).strokeBorder(accent.color, lineWidth: 1))
        .padding(.bottom, Theme.Space.m)
        .transition(.opacity)
    }
}
