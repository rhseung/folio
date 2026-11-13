import Foundation

extension QuickAdd {
    public enum Value: Equatable, Sendable {
        case course(UUID)
        case due(Date?)
        case repeats(AssignmentRepeat?)
        case kind(AssignmentKind, Int)
    }

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

        // 칩은 줄만 읽으므로, 고른 값을 줄 밖에 두면 칩과 줄이 서로 다른 과목을 말할 수 있다. 낱말은 이웃에 따라 다르게
        // 읽힐 수 있으므로(시각 앞의 `오후`, 첫 낱말이 아닌 과목 코드), 쓰는 방법마다 다시 읽어 보고 `value`로 읽히면서
        // 나머지가 그대로인 첫 방법을 고른다.
        public func line(_ line: String, setting value: Value) -> String {
            var value = value
            // 줄은 분 단위만 담으므로, 고른 날짜의 초는 다시 읽히지 않는다.
            if case let .due(date?) = value, let minute = calendar.dateInterval(of: .minute, for: date)?.start { value = .due(minute) }

            let before = read(line)
            let tries: [String]
            switch value {
            case let .course(id):
                guard before.courseId != id, let course = courses.first(where: { $0.id == id }) else { return line }
                // 코드는 줄의 첫 낱말일 때만 읽히므로, 입력한 대로의 전체 제목을 먼저 쓰고 그다음에 코드를 쓴다.
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
                let letter = before.due.map { AssignmentRepeat.weekdayLetters[calendar.isoWeekday(of: $0) - 1] } ?? ""
                let plain = line.splicing(before.repeatRanges.map { (line.wordRange($0), "") } + before.weekdayRanges.map { ($0, letter) })
                let stripped = read(plain)
                // 낱말을 빼면 이웃 낱말이 다르게 읽힐 수 있으므로, 옛 규칙의 낱말을 그 자리에서 바꾼다. `오후 3일마다 18:00`에서는
                // `오후`가 시각에 붙고, `한 달마다 까지`에서는 `까지`가 제목에 남는다.
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
                    guard let due = before.due, let first = before.dueRanges.first else {
                        tries = [plain, line.splicing(before.dueRanges.map { (line.wordRange($0), "") })]
                        break
                    }
                    // 규칙을 뺀 `오후 3일마다 18:00`은 `오후`를 시각에 붙여 시각의 일부로 읽는다. 날짜를 모두 적으면 둘이 떨어진다.
                    tries = [
                        plain, line.splicing([(first, text(of: due))] + before.dueRanges.dropFirst().map { (line.wordRange($0), "") }),
                    ]
                case let rule? where rule.weekdays.isEmpty:
                    tries =
                        swapped(rule.phrase)
                        + (stripped.dueRanges.first.map { [plain.splicing([($0.lowerBound..<$0.lowerBound, rule.phrase + " ")])] } ?? [])
                        + [plain.appending(word: rule.phrase)]
                case let rule?:
                    guard let due = before.due else {
                        tries = [plain.appending(word: rule.phrase)] + swapped(rule.phrase)
                        break
                    }
                    let words = rule.phrase + " " + text(of: due).split(separator: " ").last!
                    let ranges = stripped.dueRanges.map(plain.wordRange)
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

        func text(of date: Date) -> String {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let day = LocalDate(date, in: calendar)
            let today = LocalDate(now, in: calendar)
            let short = QuickAdd.ahead(month: day.month, day: day.day, today: today, year: today.year) == day
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return (short ? "\(day.month)/\(day.day)" : "\(day.year)/\(day.month)/\(day.day)") + " " + time
        }

        func code(_ course: Course) -> String? {
            guard let id = course.codes.first, let prefix = codes.first(where: { $0.id == id })?.prefix else { return nil }
            return prefix + (course.number.split(separator: "-").first.map(String.init) ?? "")
        }

        func holds(_ value: Value, _ after: QuickAdd, over before: QuickAdd) -> Bool {
            let same = (
                course: after.courseId == before.courseId, due: after.due == before.due, repeats: after.repeats == before.repeats,
                title: after.title == before.title, kind: after.kind == before.kind && after.number == before.number
            )
            switch value {
            case let .course(id): return after.courseId == id && same.due && same.repeats && same.title && same.kind
            case let .due(date):
                return after.due == date && after.repeats == (date == nil ? nil : before.repeats) && same.course && same.title && same.kind
            case let .repeats(repeats):
                guard let rule = repeats, !rule.weekdays.isEmpty else {
                    return after.repeats == repeats && same.course && same.due && same.title && same.kind
                }
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
