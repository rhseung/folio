import FolioDomain
import SwiftUI

struct SidebarLabelStyle: LabelStyle {
    static let gap = Theme.Space.s

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Self.gap) {
            configuration.icon
            configuration.title
        }
    }
}
