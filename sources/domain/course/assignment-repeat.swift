import Foundation

public struct AssignmentRepeat: Hashable, Sendable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case day, week, month
    }

    public var every: Int
    public var unit: Unit
    public var weekdays: [Int]

    public init(every: Int = 1, _ unit: Unit, weekdays: [Int] = []) {
        self.every = max(1, every)
        self.unit = unit
        self.weekdays = unit == .week ? Array(Set(weekdays.filter { (1...7).contains($0) })).sorted() : []
    }

    public static let daily = Self(.day)
    public static let weekly = Self(.week)
    public static let biweekly = Self(every: 2, .week)
    public static let monthly = Self(.month)
    public static let presets = [daily, weekly, biweekly, monthly]

    public func normalized(dueWeekday: Int?) -> Self {
        weekdays.count == 1 && weekdays.first == dueWeekday ? Self(every: every, unit) : self
    }

    // MARK: Next deadline

    // 월 단위 규칙의 `day`는 반복의 첫 날짜이므로, 30일로 당겨진 31일도 다음 달에는 31일로 돌아간다. 날을 24시간이
    // 아니라 달력으로 더해야 일광 절약 시간이 바뀌어도 마감 시각이 그대로다.
    public func next(after due: Date, day: Int? = nil, calendar: Calendar) -> Date {
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: every, to: due)!
        case .week:
            guard let first = weekdays.first else { return calendar.date(byAdding: .day, value: 7 * every, to: due)! }
            let today = calendar.isoWeekday(of: due)
            let days = weekdays.first { $0 > today }.map { $0 - today } ?? 7 * every - today + first
            return calendar.date(byAdding: .day, value: days, to: due)!
        case .month:
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            let start = calendar.date(from: DateComponents(year: c.year, month: (c.month ?? 1) + every, day: 1))!
            let length = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
            let month = calendar.dateComponents([.year, .month], from: start)
            return calendar.date(
                from: DateComponents(
                    year: month.year, month: month.month, day: min(day ?? c.day ?? 1, length),
                    hour: c.hour, minute: c.minute, second: c.second))!
        }
    }

    // MARK: Words

    // 빠른 추가 줄이 읽는 데이터이므로 카탈로그가 아니라 코드에 둔다.
    public var phrase: String {
        let base =
            switch (unit, every) {
            case (.day, 1): "매일"
            case (.day, _): "\(every)일마다"
            case (.week, 1): "매주"
            case (.week, 2): "격주"
            case (.week, _): "\(every)주마다"
            case (.month, 1): "매달"
            case (.month, _): "\(every)개월마다"
            }
        return weekdays.isEmpty ? base : base + " " + weekdays.map { Self.weekdayLetters[$0 - 1] }.joined()
    }

    public var label: String {
        let base: String =
            switch (unit, every) {
            case (.day, 1): String(localized: .repeatDaily)
            case (.day, _): String(localized: .repeatEveryDays(every))
            case (.week, 1): String(localized: .repeatWeekly)
            case (.week, 2): String(localized: .repeatBiweekly)
            case (.week, _): String(localized: .repeatEveryWeeks(every))
            case (.month, 1): String(localized: .repeatMonthly)
            case (.month, _): String(localized: .repeatEveryMonths(every))
            }
        guard !weekdays.isEmpty else { return base }
        return String(localized: .repeatOnWeekdays(base, weekdays.map { ClassTime.weekdayNames[$0 - 1] }.joined(separator: ", ")))
    }

    static let weekdayLetters = ["월", "화", "수", "목", "금", "토", "일"]

    static let named: [String: AssignmentRepeat] = [
        "매일": .daily, "날마다": .daily, "매일마다": .daily, "하루마다": .daily, "하루에한번": .daily,
        "격일": Self(every: 2, .day), "이틀마다": Self(every: 2, .day), "하루걸러": Self(every: 2, .day),
        "매주": .weekly, "매주마다": .weekly, "주마다": .weekly, "일주일마다": .weekly, "일주일에한번": .weekly, "주에한번": .weekly,
        "격주": .biweekly, "격주마다": .biweekly,
        "매달": .monthly, "매월": .monthly, "매달마다": .monthly, "매월마다": .monthly, "달마다": .monthly, "달에한번": .monthly,
        "격월": Self(every: 2, .month),
    ]

    static func word(_ text: String) -> AssignmentRepeat? {
        if let rule = named[text] { return rule }
        if let m = text.wholeMatch(of: /(\d{1,2})(일|주일|주|달|개월)(마다|에한번)/), let n = Int(m.1), n >= 1 {
            return AssignmentRepeat(every: n, m.2 == "일" ? .day : m.2 == "달" || m.2 == "개월" ? .month : .week)
        }
        if let m = text.wholeMatch(of: /(한|두|세)(주|달)(마다|에한번)/) {
            return AssignmentRepeat(every: m.1 == "한" ? 1 : m.1 == "두" ? 2 : 3, m.2 == "주" ? .week : .month)
        }
        return nil
    }

    static let weekdaySets: [String: [Int]] = ["평일": [1, 2, 3, 4, 5], "주말": [6, 7]]

    static func weekdayWord(_ text: String) -> (days: [Int], each: Bool)? {
        let each = text.hasSuffix("마다") && text.count > 2
        let core = each ? String(text.dropLast(2)) : text
        if let days = weekdaySets[core] { return (days, each) }
        let parts = core.split(whereSeparator: { ",·/、".contains($0) }).map(String.init)
        var days: [Int] = []
        if parts.count == 1, core.count > 1, !core.hasSuffix("요일") {
            for c in core {
                guard let i = weekdayLetters.firstIndex(of: String(c)) else { return nil }
                days.append(i + 1)
            }
        } else {
            for p in parts {
                let letter = p.hasSuffix("요일") && p.count == 3 ? String(p.prefix(1)) : p
                guard let i = weekdayLetters.firstIndex(of: letter) else { return nil }
                days.append(i + 1)
            }
        }
        guard !days.isEmpty, Set(days).count == days.count, each || days.count > 1 else { return nil }
        return (days.sorted(), each)
    }

    static func weekdayList(_ words: [String]) -> (days: [Int], each: Bool)? {
        guard let last = words.last else { return nil }
        return weekdayWord((words.dropLast().map(listItem) + [last]).joined(separator: ","))
    }

    static func listItem(_ word: String) -> String {
        if let c = word.last, ",·/、".contains(c) { return String(word.dropLast()) }
        if word.count > 1, word.hasSuffix("과") || word.hasSuffix("와") { return String(word.dropLast()) }
        return word
    }

    public init?(text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let halves = text.split(separator: ":", maxSplits: 1).map(String.init)
        let head = halves.first ?? "", days = halves.count > 1 ? halves[1] : nil
        let english = ["daily": Self.daily, "weekly": .weekly, "biweekly": .biweekly, "monthly": .monthly]
        if var rule = english[head.lowercased()] ?? Self.compact(head.lowercased()) {
            if let days {
                let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                let picked = days.lowercased().split(separator: ",").map { d in
                    names.firstIndex { d.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
                }
                guard rule.unit == .week, !picked.isEmpty, picked.allSatisfy({ $0 != nil }) else { return nil }
                rule = AssignmentRepeat(every: rule.every, .week, weekdays: picked.map { $0! + 1 })
            }
            self = rule
            return
        }
        guard days == nil else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        if let count = (1...min(4, words.count)).reversed().first(where: { Self.word(words.prefix($0).joined()) != nil }) {
            let rule = Self.word(words.prefix(count).joined())!
            let rest = Array(words.dropFirst(count))
            guard !rest.isEmpty else {
                self = rule
                return
            }
            guard rule.unit == .week, let w = Self.weekdayList(rest) ?? Self.weekdayList(Array(rest.dropLast()) + [rest.last! + "마다"])
            else { return nil }
            self = AssignmentRepeat(every: rule.every, .week, weekdays: w.days)
            return
        }
        guard let w = Self.weekdayList(words) else { return nil }
        self = AssignmentRepeat(.week, weekdays: w.days)
    }

    private static func compact(_ text: String) -> AssignmentRepeat? {
        guard let m = text.wholeMatch(of: /(\d{1,2})([dwm])/), let n = Int(m.1), n >= 1 else { return nil }
        return AssignmentRepeat(every: n, m.2 == "d" ? .day : m.2 == "w" ? .week : .month)
    }
}

extension AssignmentRepeat: Codable {
    enum CodingKeys: String, CodingKey {
        case every, unit, weekdays
    }

    // 스키마 7 이전 파일은 `"weekly"` 같은 문자열을 담고 액션 입력은 규칙을 낱말로 줄 수 있으므로, 문자열은
    // `init(text:)`처럼 읽는다.
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard let rule = AssignmentRepeat(text: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a repeat: \(text)"))
            }
            self = rule
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            every: try c.decode(Int.self, forKey: .every), try c.decode(Unit.self, forKey: .unit),
            weekdays: try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(every, forKey: .every)
        try c.encode(unit, forKey: .unit)
        try c.encode(weekdays, forKey: .weekdays)
    }
}
