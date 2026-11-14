import FolioActions
import FolioDomain
import SwiftUI

enum ClassCard {
    static let tile: CGFloat = 44
    static let menu: CGFloat = 28
    static let radius = Theme.Radius.card

    struct Tile: View {
        let month: String
        let day: String
        var ink: Color = Theme.Palette.text
        var monthInk: Color = Theme.Palette.textTertiary
        var fill: Color = Theme.Palette.page
        var dashed = false

        var body: some View {
            VStack(spacing: 0) {
                Text(month).font(Theme.Typeface.label).foregroundStyle(monthInk)
                Text(day).font(Theme.Typeface.figureSmall.weight(.bold)).foregroundStyle(ink)
            }
            .frame(width: ClassCard.tile, height: ClassCard.tile)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
    }

    struct Tag: View {
        @Environment(\.accent) private var accent
        let title: String
        var symbol: String?
        var tone: Tone = .plain

        var body: some View {
            HStack(spacing: Theme.Space.xs) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(Theme.Typeface.label.monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 24)
            .background(fill, in: .capsule)
            .fixedSize()
        }

        private var foreground: Color {
            switch tone {
            case .plain: Theme.Palette.textSecondary
            case .accent: accent.ink
            default: tone.foreground
            }
        }

        private var fill: Color {
            switch tone {
            case .accent: accent.color.opacity(Theme.Opacity.onTint)
            case .success: Theme.Palette.success.opacity(Theme.Opacity.tint)
            default: tone.fill
            }
        }
    }

    struct Pill: View {
        let title: String
        var symbol: String?
        var tone: Tone = .plain
        var help: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Tag(title: title, symbol: symbol, tone: tone).contentShape(.capsule)
            }
            .buttonStyle(.pointing(.plain))
            .fixedSize()
            .help(help)
        }
    }

    struct MenuButton<Items: View>: View {
        let help: String
        @ViewBuilder var items: Items

        var body: some View {
            Menu {
                items
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: ClassCard.menu, height: ClassCard.menu).contentShape(.circle)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(help))
        }
    }
}
