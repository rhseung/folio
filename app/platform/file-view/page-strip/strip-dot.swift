import SwiftUI

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
