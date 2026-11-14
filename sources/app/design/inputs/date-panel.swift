import FolioDomain
import SwiftUI

struct DatePanel: View {
    @Environment(Workspace.self) private var workspace
    @Binding var date: Date
    var showsTime = true
    var picked: () -> Void = {}

    static let presets = [9 * 60, 12 * 60, 18 * 60, 23 * 60 + 59]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            MonthCalendar(
                date: Binding(
                    get: { date },
                    set: { day in
                        date =
                            workspace.calendar.date(byAdding: .minute, value: minuteOfDay, to: workspace.calendar.startOfDay(for: day))
                            ?? day
                        picked()
                    }))
            if showsTime {
                Divider()
                HStack(spacing: Theme.Space.s) {
                    Text(.designTime).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    TimeMenu(minute: Binding(get: { minuteOfDay }, set: { setMinute($0) }))
                }
                FlowLayout(spacing: Theme.Space.tight) {
                    ForEach(Self.presets, id: \.self) { m in
                        Button(TimeMenu.label(m)) { setMinute(m) }
                            .lineLimit(1)
                            .buttonStyle(.pointing(.plain))
                            .font(Theme.Typeface.caption.monospacedDigit())
                            .foregroundStyle(m == minuteOfDay ? Theme.Palette.text : Theme.Palette.textSecondary)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, Theme.Space.xs)
                            .background(m == minuteOfDay ? Theme.Palette.fill : .clear, in: .capsule)
                    }
                }
            }
        }
    }

    var minuteOfDay: Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func setMinute(_ m: Int) {
        let day = workspace.calendar.startOfDay(for: date)
        date = workspace.calendar.date(byAdding: .minute, value: m, to: day) ?? date
    }
}
