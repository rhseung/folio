import FolioDomain
import SwiftUI

// 선언(`SettingItem`)의 모양에서 행 하나를 그린다. 값은 항목의 키로 읽고 쓴다.
struct SettingRow: View {
    let item: SettingItem
    @Bindable var model: SettingsModel
    var last = false

    var toggle: SettingItem? { item.switchedBy.flatMap(SettingItem.item) }

    var body: some View {
        let on = toggle.map { model.value($0) == .bool(true) } ?? true
        FormRow(label: String(localized: (toggle ?? item).name), detail: model.detail(of: item), last: last) {
            control.disabled(!on).opacity(on ? 1 : Theme.Opacity.disabled)
            if let toggle { Switch(isOn: bool(toggle)) }
        }
    }

    @ViewBuilder var control: some View {
        switch item.shape {
        case .toggle:
            Switch(isOn: bool(item))
        case .number, .positive:
            let cleared = model.value(item) == .null
            Group {
                ScrubField(value: int, range: scrubRange, step: item.step)
                if let unit = item.unit { Text(unit.name).foregroundStyle(Theme.Palette.textSecondary) }
            }
            .disabled(cleared).opacity(cleared ? Theme.Opacity.disabled : 1)
            if item.optional {
                Switch(
                    isOn: Binding(
                        get: { !cleared }, set: { model.set(item, $0 ? .number(Double(item.starting ?? item.range.lowerBound)) : .null) }))
            }
        case .numbers:
            IntListField(values: ints, unit: item.unit.map { String(localized: $0.name) } ?? "", range: item.range)
        case .time:
            TimeMenu(minute: int, hours: item.hours)
        case .choice:
            ChoiceMenu(
                selection: Binding(get: { model.value(item).string ?? "" }, set: { model.set(item, .string($0)) }),
                options: item.options.map { ($0.value, String(localized: $0.name)) })
        case .text, .prose:
            InlineField(
                item.fallback.string ?? "", text: Binding(get: { model.value(item).string ?? "" }, set: { model.set(item, .string($0)) }))
        case .custom:
            EmptyView()
        }
    }

    // 끝이 없는 범위(`positive`)를 그대로 주면 접근성의 `Slider`가 눈금을 Int.max개 만들다 멈춘다. 끌어서 고르는 범위만 10년으로
    // 두고, 그보다 큰 값은 파일이나 CLI로 넣은 값을 그대로 보인다.
    var scrubRange: ClosedRange<Int> {
        guard item.shape == .positive else { return item.range }
        return item.range.lowerBound...max(3650, model.value(item).int ?? 0)
    }

    var int: Binding<Int> {
        Binding(
            get: { model.value(item).int ?? item.starting ?? item.range.lowerBound },
            set: { model.set(item, .number(Double($0))) })
    }

    var ints: Binding<[Int]> {
        Binding(
            get: {
                guard case .array(let values) = model.value(item) else { return [] }
                return values.compactMap(\.int)
            },
            set: { model.set(item, .array($0.map { .number(Double($0)) })) })
    }

    func bool(_ item: SettingItem) -> Binding<Bool> {
        Binding(get: { model.value(item) == .bool(true) }, set: { model.set(item, .bool($0)) })
    }
}

extension JSONValue {
    fileprivate var int: Int? { if case .number(let d) = self { Int(exactly: d.rounded()) } else { nil } }
    fileprivate var string: String? { if case .string(let s) = self { s } else { nil } }
}
