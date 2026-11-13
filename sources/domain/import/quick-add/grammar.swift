import Foundation

extension QuickAdd {
    // Apple의 날짜 인식기는 `다음 주`, `오후 3시`, `30일`을 `now`가 아니라 실제 시계로 읽으므로, 이웃 낱말의 결합은
    // 규칙으로 한다.
    enum Rule: CaseIterable {
        case weekBeforeWeekday
        case meridiemBeforeTime
        case minutesAfterHour
        case monthBeforeDay
        case dayAlone

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
                guard morning || QuickAdd.evening.contains(text), i + 1 < words.count, let m = words[i + 1].minute, m < 24 * 60 else {
                    return nil
                }
                let hour = m / 60
                var shifted = m
                if !morning, hour < 12 { shifted += 12 * 60 }
                // `밤 12시`는 하루의 끝이고, `오후 12시`는 정오이며, `오전 12시`는 하루가 시작하는 자정이다.
                if text == "밤", hour == 12 { shifted = 24 * 60 + m % 60 }
                if morning, hour == 12 { shifted = m % 60 }
                words[i].joined = true
                words[i + 1].piece = .time(shifted, false)
                return nil
            case .minutesAfterHour:
                guard case let .minutes(mm)? = words[i].piece, i > 0, case let .time(m, spoken)? = words[i - 1].piece, m % 60 == 0 else {
                    return nil
                }
                words[i - 1].piece = .time(m + mm, spoken)
                words[i].joined = true
                return nil
            case .monthBeforeDay:
                guard case let .month(mo)? = words[i].piece, i + 1 < words.count, case let .dayOfMonth(d)? = words[i + 1].piece else {
                    return nil
                }
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

        // 말로 한 `내일 7시까지`는 저녁이므로, 앞에 오전이 없는 1시에서 11시 사이의 마감 시각은 오후로 본다. 콜론을
        // 넣어 친 `7:00`은 시계 표기이므로 쓴 그대로 둔다.
        for i in words.indices {
            if case let .time(m, true)? = words[i].piece, (1..<12).contains(m / 60) { words[i].piece = .time(m + 12 * 60, true) }
        }
    }

    static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

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

    static func joinRules(_ words: inout [Word], line: String) {
        var i = 0
        while i < words.count {
            for count in stride(from: min(4, words.count - i), through: 2, by: -1) {
                let run = Array(words[i..<(i + count)])
                // 규칙 뒤에 따로 선 `까지`가 독립된 낱말로 남도록, `까지`는 마지막 낱말에서만 본다.
                guard adjoin(run, in: line),
                    let rule = AssignmentRepeat.word(run.dropLast().map(\.text).joined() + QuickAdd.core(run[count - 1].text))
                else { continue }
                var merged = words[i]
                merged.range = run[0].range.lowerBound..<run[count - 1].range.upperBound
                merged.text = String(line[merged.range])
                merged.piece = .repeats(rule)
                merged.normalized = ""
                words.replaceSubrange(i..<(i + count), with: [merged])
                break
            }
            i += 1
        }
    }

    static func joinWeekdays(_ words: inout [Word], line: String) {
        var i = 0
        while i < words.count {
            let afterRule = i > 0 && words[i - 1].rule?.unit == .week
            for count in stride(from: min(7, words.count - i), through: 2, by: -1) {
                let run = Array(words[i..<(i + count)])
                guard adjoin(run, in: line),
                    let list = AssignmentRepeat.weekdayList(run.dropLast().map(\.text) + [QuickAdd.core(run[count - 1].text)]),
                    list.each || afterRule
                else { continue }
                var merged = words[i]
                merged.range = run[0].range.lowerBound..<run[count - 1].range.upperBound
                merged.text = String(line[merged.range])
                merged.piece = .weekdays(list.days, each: list.each)
                merged.normalized = AssignmentRepeat.weekdayLetters[list.days[0] - 1] + "요일"
                merged.joined = false
                words.replaceSubrange(i..<(i + count), with: [merged])
                break
            }
            i += 1
        }
    }

    static func adjoin(_ run: [Word], in line: String) -> Bool {
        zip(run, run.dropFirst()).allSatisfy { pair in line[pair.0.range.upperBound..<pair.1.range.lowerBound].allSatisfy(\.isWhitespace) }
    }

    // `평일`과 `주말`은 제목 낱말인 경우가 많으므로(`주말 과제 매주 금`), 규칙 바로 뒤(`매주 평일`)에서만 요일로 센다.
    static func bindWeekdays(_ words: inout [Word]) {
        let weekly = words.contains { $0.rule?.unit == .week }
        for i in words.indices where words[i].weekdayGroup?.each == false {
            let set = AssignmentRepeat.weekdaySets[QuickAdd.core(words[i].text)] != nil
            guard set ? !(i > 0 && words[i - 1].rule?.unit == .week) : !weekly else { continue }
            words[i].piece = nil
            // Apple의 날짜 인식기가 `주말`을 날짜로 읽어 제목에서 빼지 않도록 원래 글자를 남긴다.
            words[i].normalized = set ? "" : words[i].text
        }
    }

    static func markEndings(_ words: inout [Word]) {
        for i in words.indices.dropFirst() where dueEndings.contains(words[i].text) && words[i - 1].isDue {
            words[i].trailer = true
        }
    }
}
