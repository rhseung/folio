import Foundation

// 라이브러리를 쓰지 않고 직접 짠다. 한국어 마감(`다음 주 수 오후 6시`, `금까지`)을 주어진 시계로 읽는 유지되는
// Swift 패키지가 없고, Apple의 날짜 인식기는 실제 시계로 읽는다.

extension QuickAdd {
    static let weekdays: [String: Int] = ["월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6, "일": 7]
    static let relativeDays: [String: Int] = ["오늘": 0, "내일": 1, "모레": 2]
    static let dueEndings = ["까지", "마감"]
    static let morning: Set = ["오전", "아침", "새벽"]
    static let evening: Set = ["오후", "저녁", "밤"]
    static let weekWords: [String: Int] = ["이번주": 0, "다음주": 1, "담주": 1, "다다음주": 2]
    // 긴 조사부터 맞추도록 길이 순으로 둔다.
    static let particles = ["에다가", "에다", "에서", "에게", "에", "의", "은", "는", "이", "가", "을", "를", "도", "로"]

    enum Piece: Equatable {
        case weekday(Int, Int?)
        case day(LocalDate)
        case month(Int)
        case dayOfMonth(Int)
        case time(Int, Bool)
        case minutes(Int)
        case repeats(AssignmentRepeat)
        case weekdays([Int], each: Bool)

        var isDue: Bool {
            switch self {
            case .weekday, .day, .time, .repeats, .weekdays: true
            case .month, .dayOfMonth, .minutes: false
            }
        }
    }

    enum Recognizer: CaseIterable {
        case repeats, weekday, weekdays, relativeDay, clock, fullDate, numericDate, monthAndDay, month, dayOfMonth, spokenTime, minutes,
            midnight, noon

        func read(_ text: String, today: LocalDate, year: Int) -> (piece: Piece, normalized: String?)? {
            switch self {
            // Apple의 날짜 인식기는 `3일마다`의 `3일`을 3일로 읽으므로, 인식기에 넘기지 않는다.
            case .repeats:
                guard let rule = AssignmentRepeat.word(text) else { return nil }
                return (Piece.repeats(rule), "")
            case .weekday:
                let suffixed = QuickAdd.weekdays[String(text.prefix(1))].flatMap { text.hasSuffix("요일") ? $0 : nil }
                guard let w = QuickAdd.weekdays[text] ?? suffixed else { return nil }
                return (Piece.weekday(w, nil), String(text.prefix(1)) + "요일")
            // 요일로 보이게 해서, 인식기가 옆에 홀로 선 `오후`를 마감에 넣게 한다. 반복을 빼면 칩이 요일 하나를 쓰는데 그
            // 옆에서도 인식기가 그렇게 하므로, 이렇게 하지 않으면 반복을 뺄 때 제목이 바뀐다.
            case .weekdays:
                guard let w = AssignmentRepeat.weekdayWord(text) else { return nil }
                return (Piece.weekdays(w.days, each: w.each), AssignmentRepeat.weekdayLetters[w.days[0] - 1] + "요일")
            case .relativeDay:
                guard let d = QuickAdd.relativeDays[text] else { return nil }
                return (Piece.day(today.adding(days: d)), nil)
            case .clock:
                guard let m = text.wholeMatch(of: /(\d{1,2}):(\d{2})/), let h = Int(m.1), let mm = Int(m.2), h < 24, mm < 60 else {
                    return nil
                }
                return (Piece.time(h * 60 + mm, false), nil)
            case .fullDate:
                guard let m = text.wholeMatch(of: /(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})\.?/), let y = Int(m.1), let mo = Int(m.2),
                    let d = Int(m.3),
                    let day = LocalDate(year: y, month: mo, day: d)
                else { return nil }
                return (Piece.day(day), "\(y)년 \(mo)월 \(d)일")
            case .numericDate:
                guard let m = text.wholeMatch(of: /(\d{1,2})[\/.](\d{1,2})\.?/), let mo = Int(m.1), let d = Int(m.2),
                    let day = QuickAdd.ahead(month: mo, day: d, today: today, year: year)
                else { return nil }
                return (Piece.day(day), "\(mo)월 \(d)일")
            case .monthAndDay:
                guard let m = text.wholeMatch(of: /(\d{1,2})월\s*(\d{1,2})일/), let mo = Int(m.1), let d = Int(m.2),
                    let day = QuickAdd.ahead(month: mo, day: d, today: today, year: year)
                else { return nil }
                return (Piece.day(day), nil)
            case .month:
                guard let m = text.wholeMatch(of: /(\d{1,2})월/), let mo = Int(m.1), (1...12).contains(mo) else { return nil }
                return (Piece.month(mo), nil)
            case .dayOfMonth:
                guard let m = text.wholeMatch(of: /(\d{1,2})일/), let d = Int(m.1), (1...31).contains(d) else { return nil }
                return (Piece.dayOfMonth(d), nil)
            case .spokenTime:
                guard let m = text.wholeMatch(of: /(\d{1,2})시(?:(\d{1,2})분|(반))?/), let h = Int(m.1), h <= 24 else { return nil }
                let mm = m.3 != nil ? 30 : m.2.flatMap { Int($0) } ?? 0
                guard mm < 60 else { return nil }
                return (Piece.time(h * 60 + mm, true), nil)
            case .minutes:
                guard let m = text.wholeMatch(of: /(\d{1,2})분/), let mm = Int(m.1), mm < 60 else { return nil }
                return (Piece.minutes(mm), nil)
            case .midnight:
                guard text == "자정" else { return nil }
                return (Piece.time(24 * 60, false), nil)
            case .noon:
                guard text == "정오" else { return nil }
                return (Piece.time(12 * 60, false), nil)
            }
        }
    }

    struct Word {
        var text: String
        var range: Range<String.Index>
        var piece: Piece?
        var normalized: String
        var detected: (date: Date, phrase: String)?
        var inPhrase = false
        var trailer = false
        var joined = false

        var isDue: Bool { inPhrase || trailer || joined || piece?.isDue == true }

        var minute: Int? {
            if case let .time(m, _)? = piece { return m }
            return nil
        }

        var day: LocalDate? {
            if case let .day(d)? = piece { return d }
            return nil
        }

        var weekday: Int? {
            if case let .weekday(w, _)? = piece { return w }
            return nil
        }

        var weeksAhead: Int? {
            if case let .weekday(_, weeks)? = piece { return weeks }
            return nil
        }

        var rule: AssignmentRepeat? {
            if case let .repeats(r)? = piece { return r }
            return nil
        }

        var weekdayGroup: (days: [Int], each: Bool)? {
            if case let .weekdays(days, each)? = piece { return (days, each) }
            return nil
        }

        func core(in line: String) -> Range<String.Index> {
            range.lowerBound..<line.index(range.lowerBound, offsetBy: QuickAdd.core(text).count)
        }

        init(_ text: String, range: Range<String.Index>, today: LocalDate, year: Int) {
            self.init(reading: text, range: range, today: today, year: year)
            guard !isDue, let ending = QuickAdd.dueEndings.first(where: { text.hasSuffix($0) && text.count > $0.count }) else { return }
            let core = Word(reading: String(text.dropLast(ending.count)), range: range, today: today, year: year)
            guard core.isDue else { return }
            self = core
            self.text = text
        }

        private init(reading text: String, range: Range<String.Index>, today: LocalDate, year: Int) {
            self.text = text
            self.range = range
            normalized = text
            for recognizer in Recognizer.allCases {
                guard let read = recognizer.read(text, today: today, year: year) else { continue }
                piece = read.piece
                normalized = read.normalized ?? text
                return
            }
        }
    }

    static func ahead(month: Int, day: Int, today: LocalDate, year: Int) -> LocalDate? {
        guard let candidate = LocalDate(year: year, month: month, day: day) else { return nil }
        return candidate < today ? LocalDate(year: year + 1, month: month, day: day) : candidate
    }

    static func core(_ text: String) -> String {
        dueEndings.first { text.hasSuffix($0) && text.count > $0.count }.map { String(text.dropLast($0.count)) } ?? text
    }

    // MARK: Course

    // 첫 낱말이 아닌 자리에서는 짧은 낱말과 숫자나 요일이 든 낱말을 건너뛰므로, `HW5`나 `금` 같은 제목 낱말이
    // 줄임말로 읽히지 않는다.
    static func readCourse(_ found: inout [(String, Range<String.Index>)], courses: [Course], codes: [CourseCode]) -> (
        id: UUID, range: Range<String.Index>
    )? {
        if let (at, count, id) = matchCourseWords(found.map(\.0), courses: courses) {
            let range = found[at].1.lowerBound..<found[at + count - 1].1.upperBound
            found.removeSubrange(at..<(at + count))
            return (id, range)
        }
        for (i, (word, _)) in found.enumerated() {
            guard
                i == 0
                    || (word.count >= 2 && !word.contains(where: \.isNumber) && relativeDays[word] == nil
                        && weekdays[String(word.prefix(1))] == nil),
                let match = matchCourse(word, courses: courses, codes: codes)
            else { continue }
            let range = found[i].1
            found.remove(at: i)
            return (match, range)
        }
        return nil
    }

    // `일반물리학 및 연습 I`이 그 안의 더 짧은 제목으로 읽히지 않도록, 긴 제목부터 맞춘다.
    static func matchCourseWords(_ words: [String], courses: [Course]) -> (at: Int, count: Int, id: UUID)? {
        let longest = courses.map { $0.title.split(separator: " ").count }.max() ?? 0
        for count in stride(from: longest, through: 2, by: -1) where words.count >= count {
            for at in 0...(words.count - count) {
                let joined = words[at..<(at + count)].joined(separator: " ")
                let bare = particles.first { joined.hasSuffix($0) }.map { String(joined.dropLast($0.count)) }
                if let c = courses.first(where: { $0.title.contains(" ") && ($0.title == joined || $0.title == bare) }) {
                    return (at, count, c.id)
                }
            }
        }
        return nil
    }

    static func matchCourse(_ word: String, courses: [Course], codes: [CourseCode]) -> UUID? {
        if let id = matchCourseWord(word, courses: courses, codes: codes) { return id }
        guard let p = particles.first(where: { word.hasSuffix($0) && word.count > $0.count + 1 }) else { return nil }
        return matchCourseWord(String(word.dropLast(p.count)), courses: courses, codes: codes)
    }

    // 접두어보다 전체 제목을 먼저 맞춘다. 그러지 않으면 `일반물리학`을 앞에 나열된 `일반물리학실험`의 접두어로 읽는다.
    static func matchCourseWord(_ word: String, courses: [Course], codes: [CourseCode]) -> UUID? {
        let upper = word.uppercased()
        let prefixes = Dictionary(keepingFirst: codes.map { ($0.id, $0.prefix) })
        if let c = courses.first(where: { c in
            c.codes.contains { (prefixes[$0] ?? "") + (c.number.split(separator: "-").first ?? "") == upper }
        }) {
            return c.id
        }
        if let c = courses.first(where: { $0.title == word }) ?? courses.first(where: { $0.title.hasPrefix(word) }) { return c.id }
        let matches = courses.filter { isSubsequence(word, of: $0.title) }
        return matches.count == 1 ? matches[0].id : nil
    }

    static func isSubsequence(_ short: String, of long: String) -> Bool {
        var it = long.makeIterator()
        return short.allSatisfy { c in
            while let next = it.next() { if next == c { return true } }
            return false
        }
    }
}

// MARK: Kind and number

extension AssignmentKind {
    public static func parse(title: String) -> (kind: AssignmentKind, number: Int)? {
        match(in: title).map { ($0.kind, $0.number) }
    }

    // 종류 순서가 아니라 줄에서 처음 나온 것을 고른다. 번호 칩은 자기가 보이는 것을 고쳐 쓰는데, 종류 순서로
    // 고르면 `HW3 Lab2`에서 `HW3` 위에 쓴 `Report3`가 뒤의 `Lab2`로 읽혔다.
    public static func match(in line: String, outside: [Range<String.Index>] = []) -> (
        kind: AssignmentKind, number: Int, range: Range<String.Index>
    )? {
        var first: (kind: AssignmentKind, number: Int, range: Range<String.Index>)?
        for kind in allCases {
            for m in line.matches(of: try! Regex("(?i)\\b\(kind.rawValue)\\s*(\\d{1,2})(?!\\d)"))
            where !outside.contains(where: { $0.overlaps(m.range) }) {
                guard let n = (m.output[1].substring).flatMap({ Int($0) }) else { continue }
                if first.map({ m.range.lowerBound < $0.range.lowerBound }) ?? true { first = (kind, n, m.range) }
                break
            }
        }
        return first
    }

    public func folderName(_ number: Int) -> String {
        rawValue + String(format: "%02d", number)
    }

    public static func unmatchedFolders(_ folders: [String], assignments: [Assignment]) -> [String] {
        let taken = Set(assignments.map { a in parse(title: a.title).map { $0.kind.folderName($0.number) } ?? a.title })
        return folders.filter { !taken.contains($0) }.sorted()
    }
}
