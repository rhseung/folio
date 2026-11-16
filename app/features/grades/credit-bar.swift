import FolioDomain
import SwiftUI

struct CreditBar: View {
    let credits: CategoryCredits
    let goal: Double?
    let met: Bool
    var height: CGFloat = 6

    var body: some View {
        let scale = max(goal ?? 0, credits.earned + credits.inProgress, 1)
        let color = met ? Theme.Palette.success : Theme.Palette.textSecondary
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fill)
                Capsule().fill(color.opacity(Theme.Opacity.projected)).frame(
                    width: w * min(1, (credits.earned + credits.inProgress) / scale))
                Capsule().fill(color).frame(width: w * min(1, credits.earned / scale))
            }
        }
        .frame(height: height)
    }
}
