import SwiftUI

/// Days left to an exam, warming from gray two weeks out through amber to red on the day.
struct DdayChip: View {
    let days: Int

    static let horizon = 14

    /// Gray at the horizon and beyond, amber halfway, red at zero.
    static func heat(_ days: Int) -> Color {
        let t = 1 - Double(min(max(days, 0), horizon)) / Double(horizon)
        return t < 0.5 ? Theme.Palette.textSecondary.mix(with: Theme.Palette.warning, by: t * 2)
                       : Theme.Palette.warning.mix(with: Theme.Palette.danger, by: (t - 0.5) * 2)
    }

    var body: some View {
        let color = Self.heat(days)
        Text(days == 0 ? "D-day" : "D-\(days)")
            .font(Theme.Typeface.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(Theme.Inset.tag)
            .background(color.opacity(Theme.Opacity.tint), in: .capsule)
            // The last three days pulse once on appearing, so the nearest exam catches the eye.
            .phaseAnimator([false, true], trigger: days <= 3) { chip, lit in
                chip.scaleEffect(lit && days <= 3 ? 1.06 : 1)
            } animation: { _ in .easeInOut(duration: 0.5) }
    }
}
