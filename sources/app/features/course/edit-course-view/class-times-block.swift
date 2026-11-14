import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ClassTimesBlock: View {
    @Binding var schedule: [ClassTime]

    var body: some View {
        Block(
            title: String(localized: .classTimesTitle), note: String(localized: .classTimesNote),
            trailing: {
                Button(.classTimesAdd, systemImage: "plus") {
                    schedule.append(ClassTime(weekday: 1, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45))
                }
                .buttonStyle(.ghost)
            }
        ) {
            Card {
                if schedule.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .classTimesEmpty)) } }
                ForEach(schedule.indices, id: \.self) { i in
                    let slot = schedule[i]
                    CardRow(last: i == schedule.count - 1) {
                        ChoiceMenu(
                            selection: $schedule.element(at: i, fallback: slot).weekday,
                            options: (1...7).map { ($0, String(localized: .classTimesWeekday(ClassTime.weekdayNames[$0 - 1]))) })
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).startMinute)
                        Text("–").foregroundStyle(Theme.Palette.textTertiary)
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).endMinute)
                        Spacer(minLength: Theme.Space.m)
                        TextField(String(localized: .classTimesRoom), text: $schedule.element(at: i, fallback: slot).room).pill(width: 112)
                        ClassLinkButton(link: $schedule.element(at: i, fallback: slot).link)
                        Button(.commonDelete, systemImage: "minus.circle") { schedule.remove(at: i) }
                            .buttonStyle(.ghostIcon).tint(Theme.Palette.danger)
                    }
                }
            }
        }
    }
}
