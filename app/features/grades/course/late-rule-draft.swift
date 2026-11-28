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

    // 받는 기간이 0이면 감점은 쓰이지 않으므로, 감점 칸을 비워도 늦은 제출을 받지 않는 규칙(0:0)이다.
    var rule: LateRule? {
        if percent.isEmpty, Int(days) == 0 { return LateRule(percentPerDay: 0, days: 0) }
        return Double(percent).map { LateRule(percentPerDay: $0, days: Int(days)) }
    }

    var invalid: Bool {
        if percent.isEmpty { return !days.isEmpty && Int(days) != 0 }
        return !(rule?.isValid ?? false) || (!days.isEmpty && Int(days) == nil)
    }
}
