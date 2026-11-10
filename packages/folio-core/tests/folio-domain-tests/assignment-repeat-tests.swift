import FolioDomain
import Foundation
import PropertyBased
import Testing

struct AssignmentRepeatTests {
    let device = UUID()

    static func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.locale = Locale(identifier: "ko_KR")
        return c
    }

    let seoul = Self.calendar("Asia/Seoul")
    /// Clocks move here, so a day is not always 24 hours.
    let newYork = Self.calendar("America/New_York")

    func date(_ text: String, _ calendar: Calendar) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @Test func nextDeadlineByUnit() {
        let c = seoul
        let fri = date("2026-10-30 23:59", c)
        #expect(AssignmentRepeat.daily.next(after: fri, calendar: c) == date("2026-10-31 23:59", c))
        #expect(AssignmentRepeat(every: 3, .day).next(after: fri, calendar: c) == date("2026-11-02 23:59", c))
        #expect(AssignmentRepeat.weekly.next(after: fri, calendar: c) == date("2026-11-06 23:59", c))
        #expect(AssignmentRepeat.biweekly.next(after: fri, calendar: c) == date("2026-11-13 23:59", c))
        #expect(AssignmentRepeat.monthly.next(after: fri, calendar: c) == date("2026-11-30 23:59", c))
        // Monday and Wednesday: Wednesday after Monday, then Monday a week (or two) on.
        let mon = date("2026-11-02 09:00", c)
        let monWed = AssignmentRepeat(.week, weekdays: [1, 3])
        #expect(monWed.next(after: mon, calendar: c) == date("2026-11-04 09:00", c))
        #expect(monWed.next(after: date("2026-11-04 09:00", c), calendar: c) == date("2026-11-09 09:00", c))
        #expect(AssignmentRepeat(every: 2, .week, weekdays: [1, 3]).next(after: date("2026-11-04 09:00", c), calendar: c) == date("2026-11-16 09:00", c))
        // A deadline moved off the rule's days goes back onto them.
        #expect(monWed.next(after: date("2026-11-06 09:00", c), calendar: c) == date("2026-11-09 09:00", c))
    }

    @Test func aMonthlySeriesOnThe31stKeepsToTheMonthsEnd() {
        let c = seoul
        let jan = date("2027-01-31 23:59", c)
        let feb = AssignmentRepeat.monthly.next(after: jan, day: 31, calendar: c)
        #expect(feb == date("2027-02-28 23:59", c))
        #expect(AssignmentRepeat.monthly.next(after: feb, day: 31, calendar: c) == date("2027-03-31 23:59", c))
        #expect(AssignmentRepeat(every: 2, .month).next(after: date("2026-12-31 12:00", c), calendar: c) == date("2027-02-28 12:00", c))
    }

    @Test func aDeadlineKeepsItsClockTimeAcrossDaylightSaving() {
        let c = newYork
        // 2026-03-08 the clocks go forward an hour; 2026-11-01 back.
        #expect(AssignmentRepeat.daily.next(after: date("2026-03-07 23:59", c), calendar: c) == date("2026-03-08 23:59", c))
        #expect(AssignmentRepeat.weekly.next(after: date("2026-10-30 23:59", c), calendar: c) == date("2026-11-06 23:59", c))
        #expect(AssignmentRepeat.monthly.next(after: date("2026-02-28 18:00", c), calendar: c) == date("2026-03-28 18:00", c))
    }

    static let rule = zip(Gen.int(in: 1...6), Gen.int(in: 0...2), Gen.int(in: 0...127)).map { every, unit, days in
        AssignmentRepeat(every: every, [.day, .week, .month][unit], weekdays: (1...7).filter { days & (1 << ($0 - 1)) != 0 })
    }

    /// Whatever the rule and the deadline, the next one comes later, at the same clock time, on a chosen weekday, and
    /// a monthly one on its day or the month's last.
    @Test func theNextDeadlineIsLaterOnTheRulesDay() async {
        let calendars = [seoul, newYork]
        let base = date("2026-01-01 00:00", seoul)
        await propertyCheck(input: Self.rule, Gen.int(in: 0...(3 * 365 * 24 * 4)), Gen.int(in: 0...1), Gen.int(in: 1...31)) { rule, quarters, zone, day in
            let c = calendars[zone]
            let due = base.addingTimeInterval(Double(quarters) * 15 * 60)
            let next = rule.next(after: due, day: day, calendar: c)
            #expect(next > due, "\(rule) \(due)")
            let time = { (d: Date) in c.dateComponents([.hour, .minute], from: d) }
            // The same clock time, unless the clocks skip it that day.
            var wanted = c.dateComponents([.year, .month, .day], from: next)
            (wanted.hour, wanted.minute) = (time(due).hour, time(due).minute)
            if c.date(from: wanted).map({ time($0) == time(due) }) ?? false { #expect(time(next) == time(due), "\(rule) \(due) → \(next)") }
            if !rule.weekdays.isEmpty { #expect(rule.weekdays.contains(c.isoWeekday(of: next)), "\(rule) \(due) → \(next)") }
            if rule.unit == .month {
                let length = c.range(of: .day, in: .month, for: next)!.count
                #expect(c.component(.day, from: next) == min(day, length), "\(rule) \(due) → \(next)")
            }
            if rule.unit == .week, rule.weekdays.isEmpty {
                #expect(c.isoWeekday(of: next) == c.isoWeekday(of: due), "\(rule) \(due) → \(next)")
            }
        }
    }

    @Test func wordsAndLabels() {
        #expect(AssignmentRepeat(text: "weekly") == .weekly)
        #expect(AssignmentRepeat(text: "2w") == .biweekly)
        #expect(AssignmentRepeat(text: "3d") == AssignmentRepeat(every: 3, .day))
        #expect(AssignmentRepeat(text: "weekly:mon,wed") == AssignmentRepeat(.week, weekdays: [1, 3]))
        #expect(AssignmentRepeat(text: "매일") == .daily)
        #expect(AssignmentRepeat(text: "격주") == .biweekly)
        #expect(AssignmentRepeat(text: "매달") == .monthly)
        #expect(AssignmentRepeat(text: "2개월마다") == AssignmentRepeat(every: 2, .month))
        #expect(AssignmentRepeat(text: "매주 월수") == AssignmentRepeat(.week, weekdays: [1, 3]))
        #expect(AssignmentRepeat(text: "월,수마다") == AssignmentRepeat(.week, weekdays: [1, 3]))
        // Typed on its own, one weekday is kept: the deadline may fall on another day.
        #expect(AssignmentRepeat(text: "금요일마다") == AssignmentRepeat(.week, weekdays: [5]))
        #expect(AssignmentRepeat(text: "매주 금") == AssignmentRepeat(.week, weekdays: [5]))
        #expect(AssignmentRepeat(text: "daily:mon") == nil)
        #expect(AssignmentRepeat(text: "0일마다") == nil)
        #expect(AssignmentRepeat(text: "가끔") == nil)

        #expect(AssignmentRepeat.daily.label == "매일")
        #expect(AssignmentRepeat.biweekly.label == "격주")
        #expect(AssignmentRepeat(every: 3, .day).label == "3일마다")
        #expect(AssignmentRepeat(.week, weekdays: [3, 1]).label == "매주 월, 수")
        #expect(AssignmentRepeat(every: 2, .month).label == "2개월마다")
    }

    /// Every rule's line form reads back as the rule.
    @Test func thePhraseReadsBack() async {
        await propertyCheck(input: Self.rule) { rule in
            #expect(AssignmentRepeat(text: rule.phrase) == rule, "\(rule.phrase)")
        }
    }

    @Test func storedAsAnObjectAndReadFromTheOldString() throws {
        let rule = AssignmentRepeat(every: 2, .week, weekdays: [1, 3])
        let json = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(JSONValue.self, from: json)
            == .object(["every": .number(2), "unit": .string("week"), "weekdays": .array([.number(1), .number(3)])]))
        #expect(try JSONDecoder().decode(AssignmentRepeat.self, from: json) == rule)
        #expect(try JSONDecoder().decode(AssignmentRepeat.self, from: Data(#""weekly""#.utf8)) == .weekly)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AssignmentRepeat.self, from: Data(#""someday""#.utf8)) }
    }

    @Test func handingInMakesTheNextByTheRule() {
        let c = seoul
        let now = date("2026-10-26 12:00", c)
        var first = Assignment(device: device, at: now, title: "월말 보고", due: date("2026-10-31 23:59", c))
        first.repeats = .monthly
        first.status = .submitted
        var file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"), assignments: [first])
        file.continueRepeating(first.id, until: nil, calendar: c, device: device, now: now)
        #expect(file.assignments.map(\.due) == [date("2026-10-31 23:59", c), date("2026-11-30 23:59", c)])
        file.assignments[1].status = .submitted
        file.continueRepeating(file.assignments[1].id, until: nil, calendar: c, device: device, now: now)
        // The series started on the 31st, so December's falls on the 31st again, as the sheet's hint says.
        let november = file.assignments[1]
        #expect(file.nextDue(after: november.due!, rule: .monthly, title: november.title, calendar: c) == date("2026-12-31 23:59", c))
        #expect(file.assignments.last?.due == date("2026-12-31 23:59", c))
        #expect(file.assignments.allSatisfy { $0.repeats == .monthly })
    }
}
