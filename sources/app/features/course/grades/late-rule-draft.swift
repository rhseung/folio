import FolioDomain
import Foundation

// 시트의 두 칸(하루당 감점 %, 받는 날수)이다. 둘 다 비면 규칙이 없다.
struct LateRuleDraft: Equatable {
    var percent = ""
    var days = ""

    init(_ rule: LateRule?) {
        percent = rule.map { $0.percentPerDay.formatted(.number.grouping(.never)) } ?? ""
        days = rule?.days.map(String.init) ?? ""
    }

    var rule: LateRule? {
        Double(percent).map { LateRule(percentPerDay: $0, days: Int(days)) }
    }

    var invalid: Bool {
        if percent.isEmpty { return !days.isEmpty }
        return !(rule?.isValid ?? false) || (!days.isEmpty && Int(days) == nil)
    }
}
