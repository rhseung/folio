import FolioDomain
import SwiftUI

struct Avatar: View {
    let name: String
    let id: UUID
    var size: CGFloat = 26

    var body: some View {
        let colors = CourseAccent.presets.filter { $0.name != CourseColor.neutral }
        let accent = colors[Int(id.uuid.0) % colors.count].accent
        Circle().fill(accent.color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(accent.ink)
            }
    }
}
