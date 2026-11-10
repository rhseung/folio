import Foundation

extension QuickAdd {
    /// How words read beside their neighbors, tried in this order at each word. Done by rule rather than left to Apple's
    /// detector, which reads `다음 주`, `오후 3시` and `30일` against the real clock instead of `now`. A new pairing is a
    /// case here.
    enum Rule: CaseIterable {
        /// `다음 주`, `다음주`, `담주`, `이번 주` before a weekday.
        case weekBeforeWeekday
        /// `오전`, `오후`, `밤` before a time.
        case meridiemBeforeTime
        /// `3시 30분`.
        case minutesAfterHour
        /// `11월 3일`.
        case monthBeforeDay
        /// `30일` on its own: this month's, or next month's once it has passed.
        case dayAlone

        /// How many words to step over when the rule took them, so no later rule reads them again; nil to go on.
        func apply(_ words: inout [Word], at i: Int, today: LocalDate) -> Int? {
            switch self {
            case .weekBeforeWeekday:
                let text = QuickAdd.core(words[i].text)
                var weeks: Int?
                var span = 1
                if let w = QuickAdd.weekWords[text] {
                    weeks = w
                } else if i + 1 < words.count, QuickAdd.core(words[i + 1].text) == "주", let w = QuickAdd.weekWords[text + "주"] {
                    weeks = w
                    span = 2
                }
                guard let weeks, i + span < words.count, let weekday = words[i + span].weekday else { return nil }
                for k in i..<(i + span) { words[k].joined = true }
                words[i + span].piece = .weekday(weekday, weeks)
                return span
            case .meridiemBeforeTime:
                let text = QuickAdd.core(words[i].text)
                let morning = QuickAdd.morning.contains(text)
                guard morning || QuickAdd.evening.contains(text), i + 1 < words.count, let m = words[i + 1].minute, m < 24 * 60 else { return nil }
                let hour = m / 60
                var shifted = m
                if !morning, hour < 12 { shifted += 12 * 60 }
                // 밤 12시 is the day's end; 오후 12시 is noon; 오전 12시 is midnight at its start.
                if text == "밤", hour == 12 { shifted = 24 * 60 + m % 60 }
                if morning, hour == 12 { shifted = m % 60 }
                words[i].joined = true
                words[i + 1].piece = .time(shifted, false)
                return nil
            case .minutesAfterHour:
                guard case let .minutes(mm)? = words[i].piece, i > 0, case let .time(m, spoken)? = words[i - 1].piece, m % 60 == 0 else { return nil }
                words[i - 1].piece = .time(m + mm, spoken)
                words[i].joined = true
                return nil
            case .monthBeforeDay:
                guard case let .month(mo)? = words[i].piece, i + 1 < words.count, case let .dayOfMonth(d)? = words[i + 1].piece else { return nil }
                words[i].joined = true
                words[i + 1].piece = QuickAdd.ahead(month: mo, day: d, today: today, year: today.year).map { Piece.day($0) }
                return 2
            case .dayAlone:
                guard case let .dayOfMonth(d)? = words[i].piece else { return nil }
                var date = LocalDate(year: today.year, month: today.month, day: d)
                if date.map({ $0 < today }) ?? true {
                    let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
                    date = LocalDate(year: next.0, month: next.1, day: d)
                }
                if let date { words[i].piece = .day(date) }
                return nil
            }
        }
    }

    static func readNeighbors(_ words: inout [Word], today: LocalDate) {
        var i = 0
        next: while i < words.count {
            for rule in Rule.allCases {
                if let step = rule.apply(&words, at: i, today: today) {
                    i += step
                    continue next
                }
            }
            i += 1
        }
        // `내일 7시까지` said aloud is the evening: a deadline hour of 1 to 11 with no 오전 before it is p.m. `7:00` typed
        // with a colon is a clock reading and stays as written.
        for i in words.indices {
            if case let .time(m, true)? = words[i].piece, (1..<12).contains(m / 60) { words[i].piece = .time(m + 12 * 60, true) }
        }
    }

    static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Apple's detector, for what the rules leave (`모레 오후 3시` it reads whole). It sees the words as the lexicon
    /// rewrote them, so a phrase like `다음 주 금 오후 3시` stays whole.
    static func detect(_ words: inout [Word]) {
        var text = ""
        var offsets: [Range<Int>] = []
        for w in words {
            let start = text.utf16.count
            text += w.normalized
            offsets.append(start..<text.utf16.count)
            text += " "
        }
        for m in detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
            guard let date = m.date, let r = Range(m.range) else { continue }
            let hit = words.indices.filter { offsets[$0].overlaps(r) }
            guard let first = hit.first else { continue }
            for i in hit { words[i].inPhrase = true }
            words[first].detected = (date, (text as NSString).substring(with: m.range))
        }
    }

    /// `월수` names a weekly rule's weekdays only beside one (`매주 월수`, `격주 화목`) or with `마다` (`월,수마다`);
    /// otherwise it is a word of the title.
    static func bindWeekdays(_ words: inout [Word]) {
        let weekly = words.contains { $0.rule?.unit == .week }
        for i in words.indices where words[i].weekdayGroup?.each == false && !weekly {
            words[i].piece = nil
            words[i].normalized = words[i].text
        }
    }

    /// `까지` or `마감` as a word of its own belongs to the deadline before it (`금 마감`), and to the title otherwise.
    static func markEndings(_ words: inout [Word]) {
        for i in words.indices.dropFirst() where dueEndings.contains(words[i].text) && words[i - 1].isDue {
            words[i].trailer = true
        }
    }
}
