import Foundation

/// One-line add such as `선대 HW5 금 23:59` (docs/SPEC.md "과제 빠른 추가"). The result is shown before saving.
public struct QuickAdd: Equatable, Sendable {
    public var courseId: UUID?
    public var title: String
    /// Real clock time; deadlines ignore the day boundary so they are never seen late.
    public var due: Date?
    public var repeats: AssignmentRepeat?
    /// Where the words read as the deadline sit in the line, for highlighting them as typed.
    public var dueRanges: [Range<String.Index>] = []

    static let weekdays: [String: Int] = ["월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6, "일": 7]
    static let relativeDays: [String: Int] = ["오늘": 0, "내일": 1, "모레": 2]
    /// Deadline time when only a day is given.
    static let defaultMinute = 23 * 60 + 59

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
        var normalized: String
        var isDue: Bool { inPhrase || weekly || day != nil || weekday != nil || minute != nil }

        init(_ text: String, range: Range<String.Index>, today: LocalDate, year: Int) {
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
            } else if let m = text.wholeMatch(of: /(\d{1,2})[\/.](\d{1,2})\.?/), let mo = Int(m.1), let d = Int(m.2),
                      let candidate = LocalDate(year: year, month: mo, day: d) {
                // A month/day already past this year means next year.
                day = candidate < today ? LocalDate(year: year + 1, month: mo, day: d) : candidate
                normalized = "\(mo)월 \(d)일"
            }
        }
    }

    static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// - Parameter fixedCourse: set when adding from a course screen, so the line need not name the course.
    /// Apple's detector reads Korean phrases (`다음 주 화요일`, `모레 오후 3시`, `11월 3일 밤 11시`) against the real clock, so
    /// days the rules know (weekdays, `내일`, `3/2`) and `HH:MM` times come from the rules and `now` instead.
    public static func parse(_ line: String, courses: [Course], codes: [CourseCode] = [], fixedCourse: UUID? = nil, now: Date, calendar: Calendar) -> QuickAdd {
        var found = line.ranges(of: /\S+/).map { (String(line[$0]), $0) }
        var course = fixedCourse
        // The course can sit anywhere (`내일 7시 컴퓨터네트워킹에다`). Past the first word, short words and ones with digits
        // or day names are skipped, so a title word like `HW5` or `금` never reads as an abbreviation.
        if course == nil {
            for (i, (word, _)) in found.enumerated() {
                guard i == 0 || (word.count >= 2 && !word.contains(where: \.isNumber) && relativeDays[word] == nil && weekdays[String(word.prefix(1))] == nil),
                      let match = matchCourse(word, courses: courses, codes: codes) else { continue }
                course = match
                found.remove(at: i)
                break
            }
        }
        let today = LocalDate(now, in: calendar)
        var words = found.map { Word($0.0, range: $0.1, today: today, year: calendar.component(.year, from: now)) }

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
        // A bare weekday is the next one still ahead; `다음 주` and `이번 주` are left to the detector.
        if day == nil, let w = weekday?.weekday, !(due.compactMap(\.detected).first?.phrase.contains("주") ?? false) {
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
        return QuickAdd(courseId: course, title: title, due: day.map { calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: $0)! },
                        repeats: words.contains(where: \.weekly) ? .weekly : nil, dueRanges: dueRanges)
    }

    /// Particles typed after a course name (`컴퓨터네트워킹에다`), longest first.
    static let particles = ["에다가", "에다", "에서", "에게", "에", "의", "은", "는", "이", "가", "을", "를", "도", "로"]

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

    public func folderName(_ number: Int) -> String {
        rawValue + String(format: "%02d", number)
    }
}

extension ExamKind {
    /// `Midterm`, `Final`, `Quiz2`; nil for `other`, which has no standard folder.
    public func folderName(number: Int? = nil) -> String? {
        switch self {
        case .midterm: "Midterm"
        case .final: "Final"
        case .quiz: StandardLayout.quizFolderPrefix + "\(number ?? 1)"
        case .other: nil
        }
    }
}

extension AssignmentKind {
    /// Assignment folders (`HW01`, `SP02`) no assignment maps to yet; their names become the new assignments' titles.
    public static func unmatchedFolders(_ folders: [String], assignments: [Assignment]) -> [String] {
        let taken = Set(assignments.map { a in parse(title: a.title).map { $0.kind.folderName($0.number) } ?? a.title })
        return folders.filter { !taken.contains($0) }.sorted()
    }
}
