import FolioDomain
import SwiftUI

struct ProgressRing: View {
    let done: Double
    let taking: Double
    let goal: Double?
    let met: Bool
    let over: Bool

    var body: some View {
        Group {
            if over {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.Palette.warning)
            } else if met {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
            } else if let goal {
                ZStack {
                    Circle().stroke(Theme.Palette.fill, lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, (done + taking) / goal)).stroke(
                        Theme.Palette.textTertiary.opacity(0.45), lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, done / goal)).stroke(
                        Theme.Palette.textSecondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .rotationEffect(.degrees(-90))
                .padding(2)
            } else {
                Color.clear
            }
        }
        .font(Theme.Glyph.check)
        .frame(width: 16, height: 16)
    }
}
