import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct CourseColorSwatches: View {
    @Binding var token: String

    static let names: [String: LocalizedStringResource] = [
        "violet": .courseColorViolet, "blue": .courseColorBlue, "orange": .courseColorOrange, "green": .courseColorGreen,
        "pink": .courseColorPink, "olive": .courseColorOlive, "teal": .courseColorTeal, "red": .courseColorRed,
        "graphite": .courseColorGraphite,
    ]

    var body: some View {
        let chosen = token.isEmpty ? nil : CourseColor.token(token, position: 0)
        HStack(spacing: Theme.Space.xs) {
            ForEach(CourseAccent.presets, id: \.name) { preset in
                let on = preset.name == chosen
                let name = Self.names[preset.name].map { String(localized: $0) } ?? preset.name
                Button {
                    token = preset.name
                } label: {
                    Circle().fill(preset.accent.color)
                        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                        .padding(Theme.Space.xxs)
                        .overlay { if on { Circle().strokeBorder(Theme.Palette.text, lineWidth: 1.5) } }
                        .contentShape(.circle)
                }
                .buttonStyle(.pointing(.plain))
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
