import Foundation

/// How a repeating assignment comes back: every `every` days, weeks or months. A weekly rule may name the weekdays it
/// falls on (`매주 월수`); with none it falls on its deadline's weekday.
public struct AssignmentRepeat: Hashable, Sendable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case day, week, month
    }

    public var every: Int
    public var unit: Unit
    /// ISO weekdays (1 = Monday), sorted and distinct; only a weekly rule has them.
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
    /// What the pickers offer before "직접".
    public static let presets = [daily, weekly, biweekly, monthly]

    /// The rule without weekdays that only repeat the deadline's own (`매주 금` on a Friday deadline is `매주`), so it
    /// matches the preset it is.
    public func normalized(dueWeekday: Int?) -> Self {
        weekdays.count == 1 && weekdays.first == dueWeekday ? Self(every: every, unit) : self
    }

    // MARK: Next deadline

    /// The deadline after `due`, at the same clock time. A weekly rule with weekdays takes the next chosen weekday
    /// later in `due`'s week (weeks start on Monday), else the first one `every` weeks on. A monthly rule falls on
    /// `day` (the series' first day of the month, so a 31st clamped to a 30th goes back to the 31st) or the month's
    /// last day when it has fewer.
    ///
    /// Days are added on the calendar, not as 24 hours, so a deadline across a daylight-saving change keeps its time.
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
            return calendar.date(from: DateComponents(year: month.year, month: month.month, day: min(day ?? c.day ?? 1, length),
                                                      hour: c.hour, minute: c.minute, second: c.second))!
        }
    }

    // MARK: Words

    /// The rule as the quick-add line writes it and reads it back: `매일`, `3일마다`, `매주`, `격주`, `3주마다`, `매달`,
    /// `2개월마다`, with weekdays after (`매주 월수`). Data the reader takes, so it stays in code rather than the catalog.
    public var phrase: String {
        let base = switch (unit, every) {
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

    /// The rule as screens show it: "매일", "격주", "3일마다", "매주 월, 수".
    public var label: String {
        let base: String = switch (unit, every) {
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

    /// One word that is a rule by itself: `매일`, `날마다`, `매주`, `격주`, `매달`, `매월`, `3일마다`, `2주마다`,
    /// `2달마다`, `2개월마다`.
    static func word(_ text: String) -> AssignmentRepeat? {
        switch text {
        case "매일", "날마다": return .daily
        case "매주": return .weekly
        case "격주": return .biweekly
        case "매달", "매월": return .monthly
        default:
            guard let m = text.wholeMatch(of: /(\d{1,2})(일|주|달|개월)마다/), let n = Int(m.1), n >= 1 else { return nil }
            return AssignmentRepeat(every: n, m.2 == "일" ? .day : m.2 == "주" ? .week : .month)
        }
    }

    /// A word naming weekdays: two or more run together or split by `,`, `·`, `/` (`월수`, `월,수`, `월요일,수요일`),
    /// or any with `마다` after (`금요일마다`, `월,수마다`), which makes it a weekly rule by itself.
    static func weekdayWord(_ text: String) -> (days: [Int], each: Bool)? {
        let each = text.hasSuffix("마다") && text.count > 2
        let core = each ? String(text.dropLast(2)) : text
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

    /// The rule as typed on its own, for the CLI and action input: the words the quick-add line reads (`매주 월수`,
    /// `3일마다`, `월,수마다`), or `daily`, `weekly`, `biweekly`, `monthly`, `3d`, `2w`, `1m`, with weekdays after a
    /// colon (`weekly:mon,wed`).
    public init?(text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let halves = text.split(separator: ":", maxSplits: 1).map(String.init)
        let head = halves.first ?? "", days = halves.count > 1 ? halves[1] : nil
        let english = ["daily": Self.daily, "weekly": .weekly, "biweekly": .biweekly, "monthly": .monthly]
        if var rule = english[head.lowercased()] ?? Self.compact(head.lowercased()) {
            if let days {
                let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                let picked = days.lowercased().split(separator: ",").map { d in names.firstIndex { d.trimmingCharacters(in: .whitespaces).hasPrefix($0) } }
                guard rule.unit == .week, !picked.isEmpty, picked.allSatisfy({ $0 != nil }) else { return nil }
                rule = AssignmentRepeat(every: rule.every, .week, weekdays: picked.map { $0! + 1 })
            }
            self = rule
            return
        }
        guard days == nil else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.count {
        case 1:
            if let rule = Self.word(words[0]) {
                self = rule
            } else if let w = Self.weekdayWord(words[0]), w.each {
                self = AssignmentRepeat(.week, weekdays: w.days.count > 1 ? w.days : [])
            } else {
                return nil
            }
        case 2:
            guard let rule = Self.word(words[0]), rule.unit == .week, let w = Self.weekdayWord(words[1]) ?? Self.weekdayWord(words[1] + "마다") else { return nil }
            self = AssignmentRepeat(every: rule.every, .week, weekdays: w.days)
        default:
            return nil
        }
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

    /// A string is read as `init(text:)` reads it: `"weekly"` is what files before schema 7 hold, and action input
    /// may give a rule in words.
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard let rule = AssignmentRepeat(text: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a repeat: \(text)"))
            }
            self = rule
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(every: try c.decode(Int.self, forKey: .every), try c.decode(Unit.self, forKey: .unit),
                  weekdays: try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(every, forKey: .every)
        try c.encode(unit, forKey: .unit)
        try c.encode(weekdays, forKey: .weekdays)
    }
}
