import FolioDomain
import SwiftUI

struct CourseMark: View {
    let icon: String?
    let color: Color
    var font: Font = Theme.Glyph.line
    var filled = false
    var duotone = false
    var inline = false

    static let defaultIcon = "book.closed"

    var body: some View {
        if inline {
            Image(systemName: icon ?? Self.defaultIcon).foregroundStyle(color)
        } else {
            LineIcon(symbol: icon ?? Self.defaultIcon, font: font, filled: filled, duotone: duotone).foregroundStyle(color)
        }
    }
}

extension CourseMark {
    init(_ workspace: Workspace, _ id: UUID, inline: Bool = false) {
        self.init(icon: workspace.course(id)?.file.course.icon, color: workspace.accent(id).color, inline: inline)
    }
}
