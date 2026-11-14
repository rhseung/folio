import Foundation

// `settings show`와 MCP 입력 형식이 항목의 값과 모양을 같은 말로 적는다.
extension SettingItem {
    public func text(of value: JSONValue) -> String {
        switch (shape, value) {
        case (_, .null): String(localized: .settingNone)
        case (.time, .number(let d)): ClockText.minute(Int(d))
        case (.toggle, .bool(let b)): String(localized: b ? .settingOn : .settingOff)
        case (.numbers, .array(let values)): values.map { text(of: $0) }.joined(separator: ", ")
        case (.custom, .array(let a)): String(localized: .settingEntries(a.count))
        case (.custom, .object(let o)): String(localized: .settingEntries(o.count))
        case (_, .number(let d)): Int(exactly: d).map(String.init) ?? String(d)
        case (_, .string(let s)): s
        default: (try? JSONEncoder().encode(value)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }
    }

    public var shapeText: String {
        switch shape {
        case .toggle: String(localized: .settingShapeToggle)
        case .number(let r): String(localized: .settingShapeNumber(r.lowerBound, r.upperBound))
        case .positive: String(localized: .settingShapePositive)
        case .numbers(let r): String(localized: .settingShapeNumbers(r.lowerBound, r.upperBound))
        case .time(let r): String(localized: .settingShapeTime(r.lowerBound, r.upperBound))
        case .choice(let options): options.joined(separator: ", ")
        case .text: String(localized: .settingShapeText)
        case .custom: String(localized: .settingShapeCustom)
        }
    }
}
