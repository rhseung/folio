import Foundation

extension QuickAdd {
    /// A value picked on a chip under the line.
    public enum Value: Equatable, Sendable {
        case course(UUID)
        case due(Date?)
        case repeats(AssignmentRepeat?)
        case kind(AssignmentKind, Int)
    }

    /// What a line is read against: the courses it can name and the clock. The field and its chips share one, so a
    /// chip's pick is written in words the same reading takes back.
    public struct Reader: Sendable {
        public var courses: [Course]
        public var codes: [CourseCode]
        public var fixedCourse: UUID?
        public var defaultCourse: UUID?
        public var now: Date
        public var calendar: Calendar

        public init(
            courses: [Course], codes: [CourseCode] = [], fixedCourse: UUID? = nil, defaultCourse: UUID? = nil, now: Date,
            calendar: Calendar
        ) {
            self.courses = courses
            self.codes = codes
            self.fixedCourse = fixedCourse
            self.defaultCourse = defaultCourse
            self.now = now
            self.calendar = calendar
        }

        public func read(_ line: String) -> QuickAdd {
            QuickAdd.parse(
                line, courses: courses, codes: codes, fixedCourse: fixedCourse, defaultCourse: defaultCourse, now: now,
                calendar: calendar)
        }

        /// The line with `value` written into it: the words read for that value replaced, taken out when it is cleared,
        /// or added at the end when the line had none. The chips read only the line, so a pick kept anywhere else could
        /// say one course while the line says another (2026-11-09 user).
        ///
        /// Each way of writing it is read back, and the first that reads as `value` with everything else unchanged wins:
        /// a word can read differently beside its neighbors (`오후` before a time, a course's code past the first word).
        /// The line stays as it is when none does.
        public func line(_ line: String, setting value: Value) -> String {
            var value = value
            // The line holds minutes; a picked date's seconds would never read back.
            if case let .due(date?) = value, let minute = calendar.dateInterval(of: .minute, for: date)?.start { value = .due(minute) }

            let before = read(line)
            let tries: [String]
            switch value {
            case let .course(id):
                guard before.courseId != id, let course = courses.first(where: { $0.id == id }) else { return line }
                // The title as typed in full, then the code, which reads only as the line's first word.
                let names = [course.title] + (code(course).map { [$0] } ?? [])
                if let range = before.courseRanges.first {
                    tries =
                        names.map { line.splicing([(range, $0)]) }
                        + names.map { line.splicing([(line.wordRange(range), "")]).prepending($0) }
                } else {
                    tries = names.map { line.appending(word: $0) } + names.map { line.prepending($0) }
                }
            case let .due(date):
                let ranges = before.dueRanges.map(line.wordRange)
                guard let date else {
                    tries = [line.splicing(ranges.map { ($0, "") })]
                    break
                }
                let words = (before.repeats.map { $0.phrase + " " } ?? "") + text(of: date)
                let cleared = line.splicing(ranges.map { ($0, "") })
                if let first = before.dueRanges.first {
                    tries = [line.splicing([(first, words)] + ranges.dropFirst().map { ($0, "") }), cleared.appending(word: words)]
                } else {
                    tries = [line.appending(word: words)]
                }
            case let .repeats(repeats):
                guard before.repeats != repeats else { return line }
                // The rule's words out, and its weekdays down to the deadline's own (`매주 월수` due Wednesday → `수`), so
                // the deadline stays where it was.
                let letter = before.due.map { AssignmentRepeat.weekdayLetters[calendar.isoWeekday(of: $0) - 1] } ?? ""
                let plain = line.splicing(before.repeatRanges.map { (line.wordRange($0), "") } + before.weekdayRanges.map { ($0, letter) })
                let stripped = read(plain)
                // The old rule's words giving way in place, as taking them out can change how their neighbors read: `오후`
                // goes against the time in `오후 3일마다 18:00`, and `까지` is left as the title's in `한 달마다 까지`.
                let swapped = { (phrase: String) in
                    before.repeatRanges.first.map { first in
                        [
                            line.splicing(
                                [(first, phrase)] + before.repeatRanges.dropFirst().map { (line.wordRange($0), "") }
                                    + before.weekdayRanges.map { ($0, letter) })
                        ]
                    } ?? []
                }
                switch repeats {
                case nil:
                    // `매주 까지` with no day: the `까지` was the repeat's, and taken out with it.
                    guard let due = before.due, let first = before.dueRanges.first else {
                        tries = [plain, line.splicing(before.dueRanges.map { (line.wordRange($0), "") })]
                        break
                    }
                    // `오후 3일마다 18:00` without the rule puts `오후` against the time, where it reads as the time's; the
                    // date written out in full keeps them apart.
                    tries = [
                        plain, line.splicing([(first, text(of: due))] + before.dueRanges.dropFirst().map { (line.wordRange($0), "") }),
                    ]
                case let rule? where rule.weekdays.isEmpty:
                    tries =
                        swapped(rule.phrase)
                        + (stripped.dueRanges.first.map { [plain.splicing([($0.lowerBound..<$0.lowerBound, rule.phrase + " ")])] } ?? [])
                        + [plain.appending(word: rule.phrase)]
                case let rule?:
                    // The weekdays name the day, so the deadline's day words give way to them and only its time stays.
                    guard let due = before.due else {
                        tries = [plain.appending(word: rule.phrase)] + swapped(rule.phrase)
                        break
                    }
                    let words = rule.phrase + " " + text(of: due).split(separator: " ").last!
                    let ranges = stripped.dueRanges.map(plain.wordRange)
                    // Like `swapped`, with the deadline's words going too.
                    let others = (before.repeatRanges + before.weekdayRanges).filter { r in !before.dueRanges.contains { $0.overlaps(r) } }
                    let gone = (Array(before.dueRanges.dropFirst()) + others).map { (line.wordRange($0), "") }
                    let inPlace = before.dueRanges.first.map { [line.splicing([($0, words)] + gone)] } ?? []
                    tries =
                        (stripped.dueRanges.first.map { [plain.splicing([($0, words)] + ranges.dropFirst().map { ($0, "") })] } ?? [])
                        + [plain.splicing(ranges.map { ($0, "") }).appending(word: words)] + inPlace
                }
            case let .kind(kind, number):
                let word = "\(kind.rawValue)\(number)"
                tries = [before.kindRange.map { line.splicing([($0, word)]) } ?? line.appending(word: word)]
            }

            return tries.first { holds(value, read($0), over: before) } ?? line
        }

        /// The deadline as the line reads it back: `11/14 23:59`, with the year when `11/14` would read as another.
        func text(of date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let day = LocalDate(date, in: calendar)
            let today = LocalDate(now, in: calendar)
            let short = QuickAdd.ahead(month: day.month, day: day.day, today: today, year: today.year) == day
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return (short ? "\(day.month)/\(day.day)" : "\(day.year)/\(day.month)/\(day.day)") + " " + time
        }

        /// `EC4207`, as the line reads a code.
        func code(_ course: Course) -> String? {
            guard let id = course.codes.first, let prefix = codes.first(where: { $0.id == id })?.prefix else { return nil }
            return prefix + (course.number.split(separator: "-").first.map(String.init) ?? "")
        }

        /// The line reads as `value`, and the rest as it did: a pick changes its own chip and no other.
        func holds(_ value: Value, _ after: QuickAdd, over before: QuickAdd) -> Bool {
            let same = (
                course: after.courseId == before.courseId, due: after.due == before.due, repeats: after.repeats == before.repeats,
                title: after.title == before.title, kind: after.kind == before.kind && after.number == before.number
            )
            switch value {
            case let .course(id): return after.courseId == id && same.due && same.repeats && same.title && same.kind
            // Clearing the deadline takes `매주` with it, as it sits among the deadline's words.
            case let .due(date):
                return after.due == date && after.repeats == (date == nil ? nil : before.repeats) && same.course && same.title && same.kind
            case let .repeats(repeats):
                guard let rule = repeats, !rule.weekdays.isEmpty else {
                    return after.repeats == repeats && same.course && same.due && same.title && same.kind
                }
                // Weekdays move the deadline onto the first of them still ahead, at the same time.
                guard let due = after.due, after.repeats == rule.normalized(dueWeekday: calendar.isoWeekday(of: due)) else { return false }
                let time = { (d: Date) in calendar.dateComponents([.hour, .minute], from: d) }
                return rule.weekdays.contains(calendar.isoWeekday(of: due)) && before.due.map { time($0) == time(due) } ?? true
                    && same.course && same.title && same.kind
            case let .kind(kind, number): return after.kind == kind && after.number == number && same.course && same.due && same.repeats
            }
        }
    }
}

private extension String {
    /// The range widened over the spaces on one side when it is whole words, so taking it out leaves one space between
    /// its neighbors and none at either end.
    func wordRange(_ r: Range<Index>) -> Range<Index> {
        let open = r.lowerBound == startIndex || self[index(before: r.lowerBound)].isWhitespace
        let close = r.upperBound == endIndex || self[r.upperBound].isWhitespace
        guard open, close else { return r }
        var upper = r.upperBound
        while upper < endIndex, self[upper].isWhitespace { upper = index(after: upper) }
        if upper > r.upperBound { return r.lowerBound..<upper }
        var lower = r.lowerBound
        while lower > startIndex, self[index(before: lower)].isWhitespace { lower = index(before: lower) }
        return lower..<r.upperBound
    }

    /// The line with each range replaced, all against this line's indices; ranges that overlap an earlier one are left.
    func splicing(_ edits: [(Range<Index>, String)]) -> String {
        var out = ""
        var at = startIndex
        for (range, text) in edits.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) where range.lowerBound >= at {
            out += self[at..<range.lowerBound]
            out += text
            at = range.upperBound
        }
        out += self[at...]
        return out
    }

    func appending(word: String) -> String {
        isEmpty || last!.isWhitespace ? self + word : self + " " + word
    }

    func prepending(_ word: String) -> String {
        isEmpty || first!.isWhitespace ? word + self : word + " " + self
    }
}
