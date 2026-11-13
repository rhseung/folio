import Foundation

extension QuickAdd {
    static func resolve(_ words: [Word], line: String, course: UUID?, courseSpan: Span?, now: Date, calendar: Calendar) -> QuickAdd {
        let due = words.filter(\.isDue)
        var minute = due.compactMap(\.minute).first
        if minute == nil, let d = due.compactMap(\.detected).first(where: { $0.phrase.contains(/시|자정|정오/) }) {
            minute = calendar.component(.hour, from: d.date) * 60 + calendar.component(.minute, from: d.date)
            // `일요일 자정`은 일요일의 끝이다. 날짜 인식기는 이를 월요일 0:00으로 넘기므로, 날은 그대로 두고 24:00으로 센다.
            if minute == 0, d.phrase.contains(/자정|밤\s*12시/) { minute = 24 * 60 }
        }

        let start = calendar.startOfDay(for: now)
        var day: Date? = due.compactMap(\.day).first?.date(in: calendar)
        let weekday = due.first { $0.weekday != nil }
        if day == nil, let w = weekday?.weekday, let weeks = weekday?.weeksAhead {
            let monday = calendar.date(byAdding: .day, value: 1 - calendar.isoWeekday(of: start), to: start)!
            day = calendar.date(byAdding: .day, value: weeks * 7 + w - 1, to: monday)
        }

        func upcoming(_ w: Int) -> Date {
            let ahead = (w - calendar.isoWeekday(of: start) + 7) % 7
            var d = calendar.date(byAdding: .day, value: ahead, to: start)!
            if ahead == 0, calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: d)! <= now {
                d = calendar.date(byAdding: .day, value: 7, to: d)!
            }
            return d
        }
        if day == nil, let w = weekday?.weekday { day = upcoming(w) }
        let group = due.lazy.compactMap(\.weekdayGroup).first
        if day == nil, let group { day = group.days.map(upcoming).min() }
        if day == nil, let d = due.compactMap(\.detected).first(where: { $0.phrase.contains(/요일|월|일|주/) }) {
            day = calendar.startOfDay(for: d.date)
        }
        if day == nil, minute != nil { day = start }

        var spans = courseSpan.map { [$0] } ?? []
        var dueRanges: [Range<String.Index>] = []
        for w in due {
            if let last = dueRanges.last, line[last.upperBound..<w.range.lowerBound].allSatisfy(\.isWhitespace) {
                dueRanges[dueRanges.count - 1] = last.lowerBound..<w.range.upperBound
            } else {
                dueRanges.append(w.range)
            }
        }
        spans += dueRanges.map { Span(range: $0, field: .due) }

        if let m = AssignmentKind.match(in: line, outside: spans.map(\.range)) {
            spans.append(Span(range: m.range, field: .kind(m.kind, m.number)))
        }

        let title = words.filter { !$0.isDue }.map(\.text).joined(separator: " ")

        var repeats = due.lazy.compactMap(\.rule).first
        if let group, repeats == nil || repeats?.unit == .week {
            repeats = AssignmentRepeat(every: repeats?.every ?? 1, .week, weekdays: group.days.count > 1 ? group.days : [])
        }
        return QuickAdd(
            courseId: course, title: title, due: day.map { calendar.date(byAdding: .minute, value: minute ?? defaultMinute, to: $0)! },
            repeats: repeats, spans: spans, repeatRanges: due.filter { $0.rule != nil }.map { $0.core(in: line) },
            weekdayRanges: due.filter { $0.weekdayGroup != nil }.map { $0.core(in: line) })
    }
}
