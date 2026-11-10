import Foundation

// Written here rather than taken from a library: no maintained Swift package reads Korean deadlines (`다음 주 수 오후
// 6시`, `금까지`) against a given clock, and Apple's detector reads them against the real one.

extension QuickAdd {
    static let weekdays: [String: Int] = ["월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6, "일": 7]
    static let relativeDays: [String: Int] = ["오늘": 0, "내일": 1, "모레": 2]
    /// What Korean puts after a deadline word (`금요일까지`, `11/14까지`) or after the whole deadline as a word of its own
    /// (`금 마감`). They belong to the deadline, never the title.
    static let dueEndings = ["까지", "마감"]
    /// Words before a clock time that pick its half of the day.
    static let morning: Set = ["오전", "아침", "새벽"]
    static let evening: Set = ["오후", "저녁", "밤"]
    /// `다음 주 수요일`: weeks ahead of this one, for the weekday after.
    static let weekWords: [String: Int] = ["이번주": 0, "다음주": 1, "담주": 1, "다다음주": 2]
    /// Particles typed after a course name (`컴퓨터네트워킹에다`), longest first.
    static let particles = ["에다가", "에다", "에서", "에게", "에", "의", "은", "는", "이", "가", "을", "를", "도", "로"]

    /// What one word reads as by itself, before its neighbors are looked at.
    enum Piece: Equatable {
        /// A weekday 1 (Monday) to 7, and the weeks ahead of this one once `다음 주` joins it.
        case weekday(Int, Int?)
        case day(LocalDate)
        /// `11월`, waiting for its `3일`.
        case month(Int)
        /// `3일` on its own.
        case dayOfMonth(Int)
        /// Minutes into the day, and whether it was said as `7시` with no 오전 or 오후 before it.
        case time(Int, Bool)
        /// `30분` on its own, which only counts after an hour.
        case minutes(Int)
        /// `매주`, `격주`, `3일마다`: a rule by itself. Among title words it is the title's (`QuickAdd.bindRules`).
        case repeats(AssignmentRepeat)
        /// `월수`, `월,수마다`: the weekdays of a weekly rule, and whether `마다` made it one by itself. Without that or a
        /// weekly rule beside it, the word is the title's (`QuickAdd.bindWeekdays`).
        case weekdays([Int], each: Bool)

        /// Whether the word is the deadline's by itself; a month, a bare day number or `30분` is only once joined.
        var isDue: Bool {
            switch self {
            case .weekday, .day, .time, .repeats, .weekdays: true
            case .month, .dayOfMonth, .minutes: false
            }
        }
    }

    /// The deadline's recognizers, tried on a word in this order; the first that reads it wins. A new kind of deadline
    /// word is a case here.
    enum Recognizer: CaseIterable {
        case repeats, weekday, weekdays, relativeDay, clock, fullDate, numericDate, monthAndDay, month, dayOfMonth, spokenTime, minutes, midnight, noon

        /// The piece, and the word as Apple's detector should see it when that differs (`금` → `금요일`, `3/2` → `3월 2일`).
        func read(_ text: String, today: LocalDate, year: Int) -> (piece: Piece, normalized: String?)? {
            switch self {
            // Kept from Apple's detector, which reads the `3일` in `3일마다` as the 3rd.
            case .repeats:
                guard let rule = AssignmentRepeat.word(text) else { return nil }
                return (Piece.repeats(rule), "")
            case .weekday:
                let suffixed = QuickAdd.weekdays[String(text.prefix(1))].flatMap { text.hasSuffix("요일") ? $0 : nil }
                guard let w = QuickAdd.weekdays[text] ?? suffixed else { return nil }
                return (Piece.weekday(w, nil), String(text.prefix(1)) + "요일")
            // Seen as a weekday, so the detector takes a lone `오후` beside it into the deadline as it does beside the one
            // weekday the chip writes when the repeat is taken out; otherwise taking it out changed the title.
            case .weekdays:
                guard let w = AssignmentRepeat.weekdayWord(text) else { return nil }
                return (Piece.weekdays(w.days, each: w.each), AssignmentRepeat.weekdayLetters[w.days[0] - 1] + "요일")
            case .relativeDay:
                guard let d = QuickAdd.relativeDays[text] else { return nil }
                return (Piece.day(today.adding(days: d)), nil)
            case .clock:
                guard let m = text.wholeMatch(of: /(\d{1,2}):(\d{2})/), let h = Int(m.1), let mm = Int(m.2), h < 24, mm < 60 else { return nil }
                return (Piece.time(h * 60 + mm, false), nil)
            case .fullDate:
                // `2026/3/2`: what the deadline chip writes for a day `3/2` would not read as (past, or a year out).
                guard let m = text.wholeMatch(of: /(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})\.?/), let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3),
                      let day = LocalDate(year: y, month: mo, day: d) else { return nil }
                return (Piece.day(day), "\(y)년 \(mo)월 \(d)일")
            case .numericDate:
                guard let m = text.wholeMatch(of: /(\d{1,2})[\/.](\d{1,2})\.?/), let mo = Int(m.1), let d = Int(m.2),
                      let day = QuickAdd.ahead(month: mo, day: d, today: today, year: year) else { return nil }
                return (Piece.day(day), "\(mo)월 \(d)일")
            case .monthAndDay:
                guard let m = text.wholeMatch(of: /(\d{1,2})월\s*(\d{1,2})일/), let mo = Int(m.1), let d = Int(m.2),
                      let day = QuickAdd.ahead(month: mo, day: d, today: today, year: year) else { return nil }
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
                // The end of the day named with it: `금요일 자정` is the night between Friday and Saturday.
                guard text == "자정" else { return nil }
                return (Piece.time(24 * 60, false), nil)
            case .noon:
                guard text == "정오" else { return nil }
                return (Piece.time(12 * 60, false), nil)
            }
        }
    }

    /// A word of the line with what it reads as, alone and then beside its neighbors.
    struct Word {
        var text: String
        var range: Range<String.Index>
        var piece: Piece?
        var normalized: String
        var detected: (date: Date, phrase: String)?
        /// Inside a phrase Apple's detector read.
        var inPhrase = false
        /// `까지` or `마감` standing after a deadline word.
        var trailer = false
        /// Read only beside its neighbors: `오후` before a time, `다음 주` before a weekday, `30분` after an hour.
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

        /// The word without a `까지` after it, which stays where it is when the word is taken out.
        func core(in line: String) -> Range<String.Index> {
            range.lowerBound..<line.index(range.lowerBound, offsetBy: QuickAdd.core(text).count)
        }

        init(_ text: String, range: Range<String.Index>, today: LocalDate, year: Int) {
            self.init(reading: text, range: range, today: today, year: year)
            // `금요일까지` reads as `금요일`: the ending stays in the highlighted word, out of what the detector sees.
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

    /// A month and day already past this year means next year.
    static func ahead(month: Int, day: Int, today: LocalDate, year: Int) -> LocalDate? {
        guard let candidate = LocalDate(year: year, month: month, day: day) else { return nil }
        return candidate < today ? LocalDate(year: year + 1, month: month, day: day) : candidate
    }

    /// The word without a `까지` or `마감` after it.
    static func core(_ text: String) -> String {
        dueEndings.first { text.hasSuffix($0) && text.count > $0.count }.map { String(text.dropLast($0.count)) } ?? text
    }

    // MARK: Course

    /// The course the line names, taken out of its words. It can sit anywhere (`내일 7시 컴퓨터네트워킹에다`): a title of
    /// several words (`그래프 이론`, `확률과 통계`) typed in full first, then one word. Past the first word, short words and
    /// ones with digits or day names are skipped, so a title word like `HW5` or `금` never reads as an abbreviation.
    static func readCourse(_ found: inout [(String, Range<String.Index>)], courses: [Course], codes: [CourseCode]) -> (id: UUID, range: Range<String.Index>)? {
        if let (at, count, id) = matchCourseWords(found.map(\.0), courses: courses) {
            let range = found[at].1.lowerBound..<found[at + count - 1].1.upperBound
            found.removeSubrange(at..<(at + count))
            return (id, range)
        }
        for (i, (word, _)) in found.enumerated() {
            guard i == 0 || (word.count >= 2 && !word.contains(where: \.isNumber) && relativeDays[word] == nil && weekdays[String(word.prefix(1))] == nil),
                  let match = matchCourse(word, courses: courses, codes: codes) else { continue }
            let range = found[i].1
            found.remove(at: i)
            return (match, range)
        }
        return nil
    }

    /// Where a course's title of several words is typed in full, with a particle after it or not. Longest first, so
    /// `일반물리학 및 연습 I` is not read as a shorter title inside it.
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

    /// The word as typed, then without a trailing particle.
    static func matchCourse(_ word: String, courses: [Course], codes: [CourseCode]) -> UUID? {
        if let id = matchCourseWord(word, courses: courses, codes: codes) { return id }
        guard let p = particles.first(where: { word.hasSuffix($0) && word.count > $0.count + 1 }) else { return nil }
        return matchCourseWord(String(word.dropLast(p.count)), courses: courses, codes: codes)
    }

    /// Code (`EC4207`), then the whole title, then title prefix, then a unique in-order letter match (`선대` →
    /// `선형대수학`). The whole title before a prefix, or `일반물리학` would read as an `일반물리학실험` listed before it.
    static func matchCourseWord(_ word: String, courses: [Course], codes: [CourseCode]) -> UUID? {
        let upper = word.uppercased()
        let prefixes = Dictionary(keepingFirst: codes.map { ($0.id, $0.prefix) })
        if let c = courses.first(where: { c in c.codes.contains { (prefixes[$0] ?? "") + (c.number.split(separator: "-").first ?? "") == upper } }) {
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
    /// `HW5`, `hw 05`, `Lab3` → kind and number; used to name the assignment folder.
    public static func parse(title: String) -> (kind: AssignmentKind, number: Int)? {
        match(in: title).map { ($0.kind, $0.number) }
    }

    /// The first kind and number in a line that none of `outside` covers. First in the line, not in kind order: the
    /// number chip rewrites the one it shows, and with `HW3 Lab2` in kind order a `Report3` written over `HW3` read as
    /// the `Lab2` after it.
    public static func match(in line: String, outside: [Range<String.Index>] = []) -> (kind: AssignmentKind, number: Int, range: Range<String.Index>)? {
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

    /// Assignment folders (`HW01`, `SP02`) no assignment maps to yet; their names become the new assignments' titles.
    public static func unmatchedFolders(_ folders: [String], assignments: [Assignment]) -> [String] {
        let taken = Set(assignments.map { a in parse(title: a.title).map { $0.kind.folderName($0.number) } ?? a.title })
        return folders.filter { !taken.contains($0) }.sorted()
    }
}
