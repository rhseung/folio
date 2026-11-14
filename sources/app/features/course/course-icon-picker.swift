import SwiftUI

struct CourseIconPicker: View {
    @Binding var icon: String?
    let color: Color
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: Theme.Space.tight) {
                CourseMark(icon: icon, color: color)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .chip()
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.iconPickerHelp))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            CourseIconPanel(icon: icon, color: color) {
                icon = $0
                open = false
            }
        }
    }
}
