import Foundation

/// One-line add such as `선대 HW5 금 23:59`. The result is shown before saving.
public struct QuickAdd: Equatable, Sendable {
    public var courseId: UUID?
    public var title: String
    /// Real clock time; deadlines ignore the day boundary so they are never seen late.
    public var due: Date?
    public var repeats: AssignmentRepeat?
    /// Where the words read as the deadline sit in the line, for highlighting them as typed.
    public var dueRanges: [Range<String.Index>] = []
    /// Where the words naming the course sit, when the line names one.
    public var courseRanges: [Range<String.Index>] = []
    /// The kind and number in the title (`HW5`), which name the assignment's folder, and where they sit in the line.
    public var kind: AssignmentKind?
    public var number: Int?
    public var kindRange: Range<String.Index>?

    public var folderName: String? { kind.flatMap { k in number.map { k.folderName($0) } } }

    static let weekdays: [String: Int] = ["월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6, "일": 7]
    static let relativeDays: [String: Int] = ["오늘": 0, "내일": 1, "모레": 2]
    /// What Korean puts after a deadline word (`금요일까지`, `11/14까지`) or after the whole deadline as a word of its own
    /// (`금 마감`). They belong to the deadline, never the title.
    static let dueEndings = ["까지", "마감"]
    /// Deadline time when only a day is given.
    public static let defaultMinute = 23 * 60 + 59
    /// Words before a clock time that pick its half of the day.
    static let morning: Set = ["오전", "아침", "새벽"]
    static let evening: Set = ["오후", "저녁", "밤"]
    /// `다음 주 수요일`: weeks ahead of this one, for the weekday after.
    static let weekWords: [String: Int] = ["이번주": 0, "다음주": 1, "담주": 1, "다다음주": 2]

    /// The rules read the shorthand Apple's detector misses or gets wrong (`금`, `3/2`, `1:00`
    /// read as 1 p.m.) and rewrite it into words the detector also reads, so a phrase like `다음 주 금 오후 3시` stays whole.
    struct Word {
        var text: String
        var range: Range<String.Index>
        var day: LocalDate?
        var weekday: Int?
        var minute: Int?
        var detected: (date: Date, phrase: String)?
        var inPhrase = false
        var weekly = false
        /// `까지` or `마감` standing after a deadline word.
        var trailer = false
        /// Read only beside its neighbors: `오후` before a time, `다음 주` before a weekday, `30분` after an hour.
        var joined = false
        /// Weeks ahead of this one for a weekday after `다음 주` (`이번 주` is 0).
        var weeksAhead: Int?
        /// A bare `11월` waiting for its `3일`, and `3일` on its own.
        var month: Int?
        var dayOfMonth: Int?
        /// `30분` on its own, which only counts after an hour.
        var minutes: Int?
        /// `7시` with no 오전 or 오후 before it.
        var spokenHour = false
        var normalized: String
        var isDue: Bool { inPhrase || weekly || trailer || joined || day != nil || weekday != nil || minute != nil }

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
            if text == "매주" {
                weekly = true
            } else if let w = QuickAdd.weekdays[text] ?? QuickAdd.weekdays[String(text.prefix(1))].flatMap({ text.hasSuffix("요일") ? $0 : nil }) {
                weekday = w
                normalized = String(text.prefix(1)) + "요일"
            } else if let d = QuickAdd.relativeDays[text] {
                day = today.adding(days: d)
            } else if let m = text.wholeMatch(of: /(\d{1,2}):(\d{2})/), let h = Int(m.1), let mm = Int(m.2), h < 24, mm < 60 {
                minute = h * 60 + mm
            } else if let m = text.wholeMatch(of: /(\d{1,2})[\/.](\d{1,2})\.?/), let mo = Int(m.1), let d = Int(m.2) {
                day = QuickAdd.ahead(month: mo, day: d, today: today, year: year)
                if day != nil { normalized = "\(mo)월 \(d)일" }
            } else if let m = text.wholeMatch(of: /(\d{1,2})월\s*(\d{1,2})일/), let mo = Int(m.1), let d = Int(m.2) {
                day = QuickAdd.ahead(month: mo, day: d, today: today, year: year)
            } else if let m = text.wholeMatch(of: /(\d{1,2})월/), let mo = Int(m.1), (1...12).contains(mo) {
                month = mo
            } else if let m = text.wholeMatch(of: /(\d{1,2})일/), let d = Int(m.1), (1...31).contains(d) {
                dayOfMonth = d
            } else if let m = text.wholeMatch(of: /(\d{1,2})시(?:(\d{1,2})분|(반))?/), let h = Int(m.1), h <= 24 {
                let mm = m.3 != nil ? 30 : m.2.flatMap { Int($0) } ?? 0
                if mm < 60 {
                    minute = h * 60 + mm
                    spokenHour = true
                }
            } else if let m = text.wholeMatch(of: /(\d{1,2})분/), let mm = Int(m.1), mm < 60 {
                minutes = mm
            } else if text == "자정" {
                // The end of the day named with it: `금요일 자정` is the night between Friday and Saturday.
                minute = 24 * 60
            } else if text == "정오" {
                minute = 12 * 60
            }
        }
    }

    /// A month and day already past this year means next year.
    static func ahead(month: Int, day: Int, today: LocalDate, year: Int) -> LocalDate? {
        guard let candidate = LocalDate(year: year, month: month, day: day) else { return nil }
        return candidate < today ? LocalDate(year: year + 1, month: month, day: day) : candidate
    }

    /// Words that only read as part of a deadline beside their neighbors. Done by rule rather than left to Apple's
    /// detector, which reads `다음 주`, `오후 3시` and `30일` against the real clock instead of `now`.
    static func readNeighbors(_ words: inout [Word], today: LocalDate) {
        func core(_ i: Int) -> String {
            let t = words[i].text
            return dueEndings.first { t.hasSuffix($0) && t.count > $0.count }.map { String(t.dropLast($0.count)) } ?? t
        }
        var i = 0
        while i < words.count {
            let text = core(i)
            // 다음 주, 다음주, 담주, 이번 주 … before a weekday.
            var weeks: Int?, span = 1
            if let w = weekWords[text] {
                weeks = w
            } else if i + 1 < words.count, core(i + 1) == "주", let w = weekWords[text + "주"] {
                weeks = w
                span = 2
            }
            if let weeks, i + span < words.count, words[i + span].weekday != nil {
                for k in i..<(i + span) { words[k].joined = true }
                words[i + span].weeksAhead = weeks
                i += span
                continue
            }
            // 오전, 오후, 밤 … before a time.
            if morning.contains(text) || evening.contains(text), i + 1 < words.count, let m = words[i + 1].minute, m < 24 * 60 {
                let hour = m / 60
                var shifted = m
                if evening.contains(text), hour < 12 { shifted += 12 * 60 }
                // 밤 12시 is the day's end; 오후 12시 is noon; 오전 12시 is midnight at its start.
                if text == "밤", hour == 12 { shifted = 24 * 60 + m % 60 }
                if morning.contains(text), hour == 12 { shifted = m % 60 }
                words[i].joined = true
                words[i + 1].minute = shifted
                words[i + 1].spokenHour = false
            }
            // 3시 30분.
            if let mm = words[i].minutes, i > 0, let m = words[i - 1].minute, m % 60 == 0 {
                words[i - 1].minute = m + mm
                words[i].joined = true
            }
            // 11월 3일.
            if let mo = words[i].month, i + 1 < words.count, let d = words[i + 1].dayOfMonth {
                words[i].joined = true
                words[i + 1].day = ahead(month: mo, day: d, today: today, year: today.year)
                words[i + 1].dayOfMonth = nil
                i += 2
                continue
            }
            // 30일 on its own: this month's, or next month's once it has passed.
            if let d = words[i].dayOfMonth {
                var date = LocalDate(year: today.year, month: today.month, day: d)
                if date.map({ $0 < today }) ?? true {
                    let next = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
                    date = LocalDate(year: next.0, month: next.1, day: d)
                }
                words[i].day = date
            }
            i += 1
        }
        // `내일 7시까지` said aloud is the evening: a deadline hour of 1 to 11 with no 오전 before it is p.m. `7:00` typed
        // with a colon is a clock reading and stays as written.
        for i in words.indices where words[i].spokenHour {
            if let m = words[i].minute, (1..<12).contains(m / 60) { words[i].minute = m + 12 * 60 }
        }
    }

    static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// - Parameter fixedCourse: set when adding from a course's own assignments, so the line need not name the course.
    /// - Parameter defaultCourse: the course the window shows; a course named in the line wins over it.
    /// Apple's detector reads Korean phrases (`다음 주 화요일`, `모레 오후 3시`, `11월 3일 밤 11시`) against the real clock, so
    /// days the rules know (weekdays, `내일`, `3/2`) and `HH:MM` times come from the rules and `now` instead.
    public static func parse(_ line: String, courses: [Course], codes: [CourseCode] = [], fixedCourse: UUID? = nil, defaultCourse: UUID? = nil,
                             now: Date, calendar: Calendar) -> QuickAdd {
        var found = line.ranges(of: /\S+/).map { (String(line[$0]), $0) }
        var course = fixedCourse
        // The course can sit anywhere (`내일 7시 컴퓨터네트워킹에다`). Past the first word, short words and ones with digits
        // or day names are skipped, so a title word like `HW5` or `금` never reads as an abbreviation.
        // A title of several words (`그래프 이론`, `확률과 통계`) typed in full, before any one word of it is tried.
        var courseRanges: [Range<String.Index>] = []
        if course == nil, let (at, count, id) = matchCourseWords(found.map(\.0), courses: courses) {
            course = id
            courseRanges = [found[at].1.lowerBound..<found[at + count - 1].1.upperBound]
            found.removeSubrange(at..<(at + count))
        }
        if course == nil {
            for (i, (word, _)) in found.enumerated() {
                guard i == 0 || (word.count >= 2 && !word.contains(where: \.isNumber) && relativeDays[word] == nil && weekdays[String(word.prefix(1))] == nil),
                      let match = matchCourse(word, courses: courses, codes: codes) else { continue }
                course = match
                courseRanges = [found[i].1]
                found.remove(at: i)
                break
            }
        }
        if course == nil { course = defaultCourse }
        let today = LocalDate(now, in: calendar)
        var words = found.map { Word($0.0, range: $0.1, today: today, year: calendar.component(.year, from: now)) }
        readNeighbors(&words, today: today)

        var text = ""
        var spans: [Range<Int>] = []
        for w in words {
            let start = text.utf16.count
            text += w.normalized
            spans.append(start..<text.utf16.count)
            text += " "
        }
        for m in detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
            guard let date = m.date, let r = Range(m.range) else { continue }
            let hit = words.indices.filter { spans[$0].overlaps(r) }
            guard let first = hit.first else { continue }
            for i in hit { words[i].inPhrase = true }
            words[first].detected = (date, (text as NSString).substring(with: m.range))
        }

        for i in words.indices.dropFirst() where dueEndings.contains(words[i].text) && words[i - 1].isDue {
            words[i].trailer = true
        }
        let due = words.filter(\.isDue)
        var minute = due.compactMap(\.minute).first
        if minute == nil, let d = due.compactMap(\.detected).first(where: { $0.phrase.contains(/시|자정|정오/) }) {
            minute = calendar.component(.hour, from: d.date) * 60 + calendar.component(.minute, from: d.date)
            // `일요일 자정` is the end of Sunday; the detector rolls it to Monday 0:00, so keep the day and count to 24:00.
            if minute == 0, d.phrase.contains(/자정|밤\s*12시/) { minute = 24 * 60 }
        }
        let start = calendar.startOfDay(for: now)
        var day: Date? = due.compactMap(\.day).first?.date(in: calendar)
        let weekday = due.first { $0.weekday != nil }
        // `다음 주 금` is Friday of the week after this one (weeks start on Monday).
        if day == nil, let w = weekday?.weekday, let weeks = weekday?.weeksAhead {
            let monday = calendar.date(byAdding: .day, value: 1 - calendar.isoWeekday(of: start), to: start)!
            day = calendar.date(byAdding: .day, value: weeks * 7 + w - 1, to: monday)
        }
        // A bare weekday is the next one still ahead.
        if day == nil, let w = weekday?.weekday {
            let ahead = (w - calendar.isoWeekday(of: start) + 7) % 7
            var d = calendar.date(byAdding: .day, value: ahead, to: start)!
            if ahead == 0, calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: d)! <= now {
                d = calendar.date(byAdding: .day, value: 7, to: d)!
            }
            day = d
        }
        if day == nil, let d = due.compactMap(\.detected).first(where: { $0.phrase.contains(/요일|월|일|주/) }) {
            day = calendar.startOfDay(for: d.date)
        }
        if day == nil, minute != nil { day = start }

        var dueRanges: [Range<String.Index>] = []
        for w in due {
            // `금 23:59` reads as one phrase, so neighbors join across the space.
            if let last = dueRanges.last, line[last.upperBound..<w.range.lowerBound].allSatisfy(\.isWhitespace) {
                dueRanges[dueRanges.count - 1] = last.lowerBound..<w.range.upperBound
            } else {
                dueRanges.append(w.range)
            }
        }
        let title = words.filter { !$0.isDue }.map(\.text).joined(separator: " ")
        var read = QuickAdd(courseId: course, title: title, due: day.map { calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: $0)! },
                            repeats: words.contains(where: \.weekly) ? .weekly : nil, dueRanges: dueRanges, courseRanges: courseRanges)
        let taken = dueRanges + courseRanges
        if let m = AssignmentKind.match(in: line, outside: taken) {
            (read.kind, read.number, read.kindRange) = (m.kind, m.number, m.range)
        }
        return read
    }

    /// The line with its kind and number (`HW5`) changed to another, as the number chip picks it. The title is what is
    /// typed, so the folder name changes in the line rather than beside it.
    public static func renumbered(_ line: String, at range: Range<String.Index>, kind: AssignmentKind, number: Int) -> String {
        line.replacingCharacters(in: range, with: "\(kind.rawValue)\(number)")
    }

    /// Particles typed after a course name (`컴퓨터네트워킹에다`), longest first.
    static let particles = ["에다가", "에다", "에서", "에게", "에", "의", "은", "는", "이", "가", "을", "를", "도", "로"]

    /// Where a course's title of two or three words is typed in full, with a particle after it or not.
    static func matchCourseWords(_ words: [String], courses: [Course]) -> (at: Int, count: Int, id: UUID)? {
        for count in [3, 2] where words.count >= count {
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

    /// Code (`EC4207`), then title prefix, then a unique in-order letter match (`선대` → `선형대수학`).
    static func matchCourseWord(_ word: String, courses: [Course], codes: [CourseCode]) -> UUID? {
        let upper = word.uppercased()
        let prefixes = Dictionary(keepingFirst: codes.map { ($0.id, $0.prefix) })
        if let c = courses.first(where: { c in c.codes.contains { (prefixes[$0] ?? "") + (c.number.split(separator: "-").first ?? "") == upper } }) {
            return c.id
        }
        if let c = courses.first(where: { $0.title.hasPrefix(word) }) { return c.id }
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

extension AssignmentKind {
    /// `HW5`, `hw 05`, `Lab3` → kind and number; used to name the assignment folder.
    public static func parse(title: String) -> (kind: AssignmentKind, number: Int)? {
        for kind in allCases {
            if let m = title.firstMatch(of: try! Regex("(?i)\\b\(kind.rawValue)\\s*(\\d{1,2})(?!\\d)")),
               let n = (m.output[1].substring).flatMap({ Int($0) }) {
                return (kind, n)
            }
        }
        return nil
    }

    /// The first kind and number in a line that none of `outside` covers, kinds in the order `parse(title:)` tries them.
    public static func match(in line: String, outside: [Range<String.Index>] = []) -> (kind: AssignmentKind, number: Int, range: Range<String.Index>)? {
        for kind in allCases {
            for m in line.matches(of: try! Regex("(?i)\\b\(kind.rawValue)\\s*(\\d{1,2})(?!\\d)"))
            where !outside.contains(where: { $0.overlaps(m.range) }) {
                if let n = (m.output[1].substring).flatMap({ Int($0) }) { return (kind, n, m.range) }
            }
        }
        return nil
    }

    public func folderName(_ number: Int) -> String {
        rawValue + String(format: "%02d", number)
    }
}

extension AssignmentKind {
    /// Assignment folders (`HW01`, `SP02`) no assignment maps to yet; their names become the new assignments' titles.
    public static func unmatchedFolders(_ folders: [String], assignments: [Assignment]) -> [String] {
        let taken = Set(assignments.map { a in parse(title: a.title).map { $0.kind.folderName($0.number) } ?? a.title })
        return folders.filter { !taken.contains($0) }.sorted()
    }
}
