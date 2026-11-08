import Foundation

extension QuickAdd {
    /// What the read words come to: the deadline from its pieces, the spans of the line, and the title from the words in
    /// none of them. Days the rules know (weekdays, `내일`, `3/2`) and times come from the rules and `now`; the detector
    /// fills in only what they left.
    static func resolve(_ words: [Word], line: String, course: UUID?, courseSpan: Span?, now: Date, calendar: Calendar) -> QuickAdd {
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

        var spans = courseSpan.map { [$0] } ?? []
        var dueRanges: [Range<String.Index>] = []
        for w in due {
            // `금 23:59` reads as one phrase, so neighbors join across the space.
            if let last = dueRanges.last, line[last.upperBound..<w.range.lowerBound].allSatisfy(\.isWhitespace) {
                dueRanges[dueRanges.count - 1] = last.lowerBound..<w.range.upperBound
            } else {
                dueRanges.append(w.range)
            }
        }
        spans += dueRanges.map { Span(range: $0, field: .due) }
        // A number inside the deadline or the course is not the assignment's.
        if let m = AssignmentKind.match(in: line, outside: spans.map(\.range)) {
            spans.append(Span(range: m.range, field: .kind(m.kind, m.number)))
        }
        let title = words.filter { !$0.isDue }.map(\.text).joined(separator: " ")
        return QuickAdd(courseId: course, title: title, due: day.map { calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: $0)! },
                        repeats: words.contains(where: \.weekly) ? .weekly : nil, spans: spans)
    }
}
