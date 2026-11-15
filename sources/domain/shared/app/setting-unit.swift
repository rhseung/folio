import Foundation

// 숫자 항목의 값 뒤에 붙는 단위다. 설정 화면이 값 옆에 보인다.
public enum SettingUnit: String, Sendable {
    case minutes, days, daysBefore, hoursBefore, cards, passes, units

    public var name: LocalizedStringResource {
        switch self {
        case .minutes: .settingUnitMinutes
        case .days: .settingUnitDays
        case .daysBefore: .settingUnitDaysBefore
        case .hoursBefore: .settingUnitHoursBefore
        case .cards: .settingUnitCards
        case .passes: .settingUnitPasses
        case .units: .settingUnitUnits
        }
    }
}
