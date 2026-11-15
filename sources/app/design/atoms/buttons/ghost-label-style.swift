import SwiftUI

struct GhostLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.xs) {
            configuration.icon.imageScale(.small).fontWeight(.semibold)
            configuration.title.lineLimit(1)
        }
    }
}
