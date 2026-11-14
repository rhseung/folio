import SwiftUI

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
                Button {
                    withAnimation(Theme.Motion.quick) { cancel() }
                } label: {
                    Text(.commonCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghost)
                Button {
                    withAnimation(Theme.Motion.quick) { commit() }
                } label: {
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
        .padding(Theme.Space.s)
        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.strip))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.strip).strokeBorder(accent.color, lineWidth: 1))
        .padding(.bottom, Theme.Space.m)
        .transition(.opacity)
    }
}
