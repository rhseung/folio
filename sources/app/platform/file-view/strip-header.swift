import SwiftUI

enum StripMetrics {
    #if os(iOS)
    static let header: CGFloat = Theme.Size.touchTarget
    #else
    static let header: CGFloat = Theme.Size.toolbarButton - Theme.Space.xs
    #endif
}

struct StripHeader: View {
    let section: StripSection
    let open: Bool
    var lit = false
    let help: Text
    let toggle: () -> Void
    let edit: () -> Void
    @Environment(\.accent) private var accent
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button {
                withAnimation(Theme.Motion.quick) { toggle() }
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(section.kind.tinted ? accent.ink : Theme.Palette.textTertiary)
                    .frame(width: Theme.Space.m, height: StripMetrics.header)
                    .padding(.leading, Theme.Space.tight)
                    .chevronReach()
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(open ? .commonCollapse : .commonExpand))
            Button(action: edit) {
                HStack(spacing: Theme.Space.xs) {
                    Text(section.title).font(Theme.Typeface.bodyStrong).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(titleColor)
                    Spacer(minLength: Theme.Space.xs)
                    Text(section.label).font(Theme.Typeface.caption).monospacedDigit().fixedSize().foregroundStyle(
                        Theme.Palette.textSecondary)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(help)
        }
        .frame(height: StripMetrics.header)
        .padding(.trailing, Theme.Space.s)
        .background(lit ? accent.tint : hovering ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.strip))
        .onHover { hovering = $0 }
        .padding(.bottom, open ? Theme.Space.s : Theme.Space.xs)
    }

    private var titleColor: Color {
        switch section.kind {
        case .held: open ? Theme.Palette.text : Theme.Palette.textSecondary
        case .new: accent.ink
        case .none: Theme.Palette.textTertiary
        }
    }
}

private extension View {
    @ViewBuilder func chevronReach() -> some View {
        #if os(iOS)
        padding(.leading, Theme.Space.s).contentShape(.rect).padding(.leading, -Theme.Space.s)
        #else
        contentShape(.rect)
        #endif
    }
}
