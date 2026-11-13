import FolioDomain
import SwiftUI

struct RepeatMenuItems: View {
    let selection: AssignmentRepeat?
    /// The rule is edited by its parts rather than picked: one no preset matches, or "직접 설정" picked.
    let custom: Bool
    let pick: (AssignmentRepeat?) -> Void
    let customize: () -> Void

    var body: some View {
        row(String(localized: .repeatPickerNone), on: selection == nil && !custom) { pick(nil) }
        ForEach(AssignmentRepeat.presets, id: \.self) { rule in
            row(rule.label, on: selection == rule && !custom) { pick(rule) }
        }
        Divider()
        row(String(localized: .repeatPickerCustom), on: custom, action: customize)
    }

    private func row(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if on { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

/// With no weekdays the rule falls on the deadline's, so that one shows as picked and picking only it again stores none.
struct RepeatRuleRows: View {
    @Binding var rule: AssignmentRepeat
    let dueWeekday: Int?
    var last = false

    var body: some View {
        FormRow(label: String(localized: .repeatPickerInterval), last: last && rule.unit != .week) {
            ScrubField(
                value: Binding(get: { Double(rule.every) }, set: { set(every: Int($0.rounded())) }), range: 1...30, step: 1, width: 72)
            Segmented(
                selection: Binding(get: { rule.unit }, set: { set(unit: $0) }),
                options: [
                    (.day, String(localized: .repeatPickerDays)), (.week, String(localized: .repeatPickerWeeks)),
                    (.month, String(localized: .repeatPickerMonths)),
                ])
        }
        if rule.unit == .week {
            FormRow(label: String(localized: .repeatPickerWeekdays), last: last) {
                WeekdayToggles(selection: Binding(get: { shownDays }, set: { set(weekdays: $0) }))
            }
        }
    }

    private var shownDays: Set<Int> { rule.weekdays.isEmpty ? Set(dueWeekday.map { [$0] } ?? []) : Set(rule.weekdays) }

    private func set(every: Int? = nil, unit: AssignmentRepeat.Unit? = nil, weekdays: Set<Int>? = nil) {
        let days = unit.map { $0 == .week ? rule.weekdays : [] } ?? weekdays.map { Array($0) } ?? rule.weekdays
        rule = AssignmentRepeat(every: every ?? rule.every, unit ?? rule.unit, weekdays: days).normalized(dueWeekday: dueWeekday)
    }
}

/// At least one stays on: a weekly rule falls on some day.
struct WeekdayToggles: View {
    @Binding var selection: Set<Int>
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(1...7, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { if selection.count > 1 { selection.remove(day) } } else { selection.insert(day) }
                } label: {
                    Text(ClassTime.weekdayNames[day - 1])
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.Palette.onFill : Theme.Palette.textSecondary)
                        .frame(width: 28, height: 28)  // design: one-off, a one-letter day in a round toggle
                        // Filled, not tinted: beside the neighbors' gray a tint barely showed which days were on.
                        .background(on ? accent.fill : Theme.Palette.fill, in: .circle)
                        .contentShape(TouchTarget())
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
