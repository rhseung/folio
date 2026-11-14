import FolioDomain
import SwiftUI

struct DailyBars: View {
    @Environment(\.accent) private var accent
    let counts: [(day: LocalDate, count: Int)]
    let today: LocalDate

    var body: some View {
        let top = max(counts.map(\.count).max() ?? 0, 1)
        Card(padding: Theme.Space.l) {
            HStack(alignment: .bottom, spacing: Theme.Space.tight) {
                ForEach(counts, id: \.day) { day, n in
                    VStack(spacing: Theme.Space.xs) {
                        Text(n > 0 ? "\(n)" : "").font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
                        RoundedRectangle(cornerRadius: Theme.Radius.small)
                            .fill(n > 0 ? accent.color : Theme.Palette.fill)
                            .frame(height: max(4, 70 * CGFloat(n) / CGFloat(top)))
                        Text("\(day.day)").font(Theme.Typeface.label.weight(.regular))
                            .foregroundStyle(day == today ? accent.ink : Theme.Palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
    }
}
