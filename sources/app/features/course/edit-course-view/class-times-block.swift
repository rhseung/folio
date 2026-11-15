import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ClassTimesBlock: View {
    @Binding var schedule: [ClassTime]
    let newTime: ClassTime

    var body: some View {
        Block(
            title: String(localized: .classTimesTitle), note: String(localized: .classTimesNote),
            trailing: {
                Button(.classTimesAdd, systemImage: "plus") {
                    schedule.append(newTime)
                }
                .buttonStyle(.ghost)
            }
        ) {
            Card {
                if schedule.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .classTimesEmpty)) } }
                ForEach(schedule.indices, id: \.self) { i in
                    let slot = schedule[i]
                    CardRow(last: i == schedule.count - 1) {
                        Select(
                            selection: $schedule.element(at: i, fallback: slot).weekday,
                            options: (1...7).map { ($0, String(localized: .classTimesWeekday(ClassTime.weekdayNames[$0 - 1]))) })
                        TimePicker(selection: $schedule.element(at: i, fallback: slot).startMinute)
                        Text("–").foregroundStyle(Theme.Palette.textTertiary)
                        TimePicker(selection: $schedule.element(at: i, fallback: slot).endMinute)
                        Spacer(minLength: Theme.Space.m)
                        TextField(String(localized: .classTimesRoom), text: $schedule.element(at: i, fallback: slot).room).pill(
                            width: Theme.Size.shortTextField)
                        ClassLinkButton(link: $schedule.element(at: i, fallback: slot).link)
                        Button(.commonDelete, systemImage: "minus.circle") { schedule.remove(at: i) }
                            .buttonStyle(.ghostIcon).tint(Theme.Palette.danger)
                    }
                }
            }
        }
    }
}
