import FolioDomain
import SwiftUI

struct TallyRow: View {
    let title: String
    let tally: WrongTally
    let items: (Int) -> LocalizedStringResource
    let last: Bool

    var body: some View {
        CardRow(last: last) {
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(items(tally.items)).foregroundStyle(Theme.Palette.textTertiary).frame(width: Theme.Size.numberColumn, alignment: .trailing)
            ProgressBar(value: tally.accuracy ?? 0).frame(width: Theme.Size.meter)
            Text(tally.accuracyText).frame(width: Theme.Size.percentColumn, alignment: .trailing)
            Text(.quizOpenCount(tally.open)).foregroundStyle(tally.open > 0 ? Theme.Palette.danger : Theme.Palette.textTertiary).frame(
                width: Theme.Size.numberColumn, alignment: .trailing)
            Text(.quizResolvedCount(tally.resolved)).foregroundStyle(Theme.Palette.textTertiary).frame(
                width: Theme.Size.numberColumn, alignment: .trailing)
        }
        .font(Theme.Typeface.body.monospacedDigit())
    }
}
