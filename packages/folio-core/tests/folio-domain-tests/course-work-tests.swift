import FolioDomain
import Foundation
import Testing

struct CourseWorkTests {
    let device = UUID()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    // MARK: Sessions

    // Mon/Wed 13:00-14:15. 2026-10-26 is a Monday.
    var monWed: [ClassTime] { [ClassTime(weekday: 1, startMinute: 780, endMinute: 855, room: "203"), ClassTime(weekday: 3, startMinute: 780, endMinute: 855)] }

    @Test func suggestsTheLectureUnderWayThenTheNextOne() {
        let during = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: nil, to: nil, now: date("2026-10-26 13:30"), calendar: calendar)
        #expect(during?.date == date("2026-10-26 13:00") && during?.end == date("2026-10-26 14:15") && during?.room == "203")
        let after = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: nil, to: nil, now: date("2026-10-26 14:15"), calendar: calendar)
        #expect(after?.date == date("2026-10-28 13:00"))
    }

    @Test func aSessionAtThatTimeEvenCancelledMovesTheSuggestionOn() {
        var cancelled = Session(device: device, at: .now, week: 9, date: date("2026-10-26 13:00"))
        cancelled.isCancelled = true
        let dateOnly = Session(device: device, at: .now, week: 9, date: date("2026-10-28 00:00"))
        let s = SessionPlanner.suggestion(schedule: monWed, sessions: [cancelled, dateOnly], from: nil, to: nil, now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(s?.date == date("2026-11-02 13:00"))
    }

    /// 2026 fall starts Monday 8/31, so 10/19 opens week 8, the default midterm week.
    @Test func examWeeksHoldNoLectures() {
        let fall = Semester(device: device, at: .now, year: 2026, term: .fall, start: LocalDate("2026-08-31"), end: LocalDate("2026-12-18"))
        #expect(fall.examWeeks == [8, 16])
        let skipped = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: fall.start, to: fall.end, examWeeks: fall.examWeeks,
                                                now: date("2026-10-19 09:00"), calendar: calendar)
        #expect(skipped?.date == date("2026-10-26 13:00"))
        // An exam held in class time is part of that class, so the class still comes.
        let held = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: fall.start, to: fall.end, examWeeks: fall.examWeeks,
                                             now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(held?.date == date("2026-10-26 13:00"))
        #expect(Semester(device: device, at: .now, year: 2026, term: .summer).examWeeks.isEmpty)
    }

    @Test func noSuggestionOutsideTheTerm() {
        let ended = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: nil, to: LocalDate("2026-10-27"), now: date("2026-10-26 15:00"), calendar: calendar)
        #expect(ended == nil)
        let before = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: LocalDate("2026-10-28"), to: nil, now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(before?.date == date("2026-10-28 13:00"))
    }

    /// A 휴강 two weeks off needs a class to mark: the plan runs to the term's end, past the classes already made.
    @Test func plannedClassesRunToTheTermsEnd() {
        var cancelled = Session(device: device, at: .now, week: 11, date: date("2026-11-09 13:00"))
        cancelled.isCancelled = true
        let made = Session(device: device, at: .now, week: 10, date: date("2026-11-04 13:00"))
        let plan = SessionPlanner.planned(schedule: monWed, sessions: [cancelled, made], from: LocalDate("2026-09-02"), to: LocalDate("2026-11-25"),
                                          now: date("2026-11-03 09:00"), calendar: calendar)
        #expect(plan.map(\.date) == ["2026-11-11 13:00", "2026-11-16 13:00", "2026-11-18 13:00", "2026-11-23 13:00", "2026-11-25 13:00"].map(date))
        // Without an end, the coming week only, as the suggestion always did.
        let open = SessionPlanner.planned(schedule: monWed, sessions: [], from: nil, to: nil, now: date("2026-11-03 09:00"), calendar: calendar)
        #expect(open.map(\.date) == ["2026-11-04 13:00", "2026-11-09 13:00"].map(date))
        #expect(SessionPlanner.suggestion(schedule: monWed, sessions: [made], from: nil, to: nil, now: date("2026-11-03 09:00"), calendar: calendar)?.date
                == date("2026-11-09 13:00"))
        // A hand-edited term whose start is after its end plans nothing instead of running on.
        let flipped = SessionPlanner.planned(schedule: monWed, sessions: [], from: LocalDate("2026-12-01"), to: LocalDate("2026-11-25"),
                                             now: date("2026-11-03 09:00"), calendar: calendar)
        #expect(flipped.isEmpty)
    }

    /// The class began late, or came in from a calendar event a few minutes off the slot: still that class.
    @Test func aSessionInsideTheSlotStandsForIt() {
        let late = Session(device: device, at: .now, week: 10, date: date("2026-11-04 13:30"))
        let makeup = Session(device: device, at: .now, week: 11, date: date("2026-11-09 18:00"))
        let plan = SessionPlanner.planned(schedule: monWed, sessions: [late, makeup], from: nil, to: LocalDate("2026-11-11"),
                                          now: date("2026-11-03 09:00"), calendar: calendar)
        #expect(plan.map(\.date) == ["2026-11-09 13:00", "2026-11-11 13:00"].map(date))
    }

    @Test func plannedClassesSitInTheirWeeksOnTheTimeline() {
        let made = Session(device: device, at: .now, week: 10, date: date("2026-11-04 13:00"))
        let planned = Session(device: device, at: .now, week: 10, date: date("2026-11-02 13:00"))
        let items = SessionTimeline.items(CourseFile(course: courses[0], sessions: [made]), planned: [planned], classMinutes: 75, calendar: calendar)
        #expect(items.map(\.id) == ["week-10", "planned-\(planned.date.timeIntervalSinceReferenceDate)", made.id.uuidString])
    }

    @Test func newSessionsCountWeeksFromTheTermStart() {
        // Term starts Wednesday 2026-09-02: that week is 1, so 2026-10-26 is 9주차.
        let first = SessionPlanner.session(at: date("2026-10-26 13:00"), sessions: [], termStart: LocalDate("2026-09-02"),
                                           calendar: calendar, device: device, now: .now)
        #expect(first.week == 9 && first.name(among: [first]) == "9주차-1")
        let recitation = SessionPlanner.session(at: date("2026-10-27 19:00"), sessions: [first], termStart: LocalDate("2026-09-02"),
                                                calendar: calendar, device: device, now: .now)
        let second = SessionPlanner.session(at: date("2026-10-28 13:00"), sessions: [first, recitation], termStart: LocalDate("2026-09-02"),
                                            calendar: calendar, device: device, now: .now)
        let all = [first, recitation, second]
        #expect(all.map { $0.name(among: all) } == ["9주차-1", "9주차-2", "9주차-3"])
        // Without a term start, weeks count from the earliest session.
        let later = SessionPlanner.session(at: date("2026-11-02 13:00"), sessions: all, termStart: nil, calendar: calendar, device: device, now: .now)
        #expect(later.week == 2)
    }

    @Test func untouchedFutureSessionsLeaveAnythingUsedAlone() {
        let now = date("2026-10-26 12:00")
        func at(_ s: String) -> Session { Session(device: device, at: .now, week: 9, date: date(s)) }
        let past = at("2026-10-19 13:00"), empty = at("2026-11-02 13:00"), noted = at("2026-11-04 13:00"), unitLinked = at("2026-11-09 13:00")
        var topic = at("2026-11-11 13:00"); topic.topic = "행렬식"
        var online = at("2026-11-12 21:00"); online.link = "https://zoom.us/j/1"
        var makeup = at("2026-11-13 21:00"); makeup.end = date("2026-11-13 22:15")
        var cancelled = Session(device: device, at: .now, week: 10, date: date("2026-11-16 13:00"))
        cancelled.isCancelled = true
        var unit = Unit(device: device, at: .now, title: "고윳값", order: 1)
        unit.sessionIds = [unitLinked.id]
        let file = CourseFile(course: courses[0], units: [unit], sessions: [past, empty, noted, unitLinked, topic, online, makeup, cancelled])
        #expect(file.untouchedFutureSessions(now: now, notedSessions: [noted.id]).map(\.id) == [empty.id])
    }

    /// A past session can be deleted too, as long as nothing points at it.
    @Test func onlyAnUnlinkedSessionIsDeletable() {
        let held = Session(device: device, at: .now, week: 8, date: date("2026-10-19 13:00"))
        let attended = Session(device: device, at: .now, week: 8, date: date("2026-10-21 13:00"))
        var file = CourseFile(course: courses[0], sessions: [held, attended])
        file.attendance = [Attendance(device: device, at: .now, sessionId: attended.id, state: .late)]
        #expect(file.isUnlinked(held, notedSessions: []))
        #expect(!file.isUnlinked(held, notedSessions: [held.id]))
        #expect(!file.isUnlinked(attended, notedSessions: []))
    }

    @Test func anAbsenceMarkedAheadCountsFromItsClass() {
        let held = Session(device: device, at: .now, week: 9, date: date("2026-10-26 13:00"))
        let ahead = Session(device: device, at: .now, week: 10, date: date("2026-11-02 13:00"))
        var file = CourseFile(course: courses[0], sessions: [held, ahead])
        file.attendance = [held, ahead].map { Attendance(device: device, at: .now, sessionId: $0.id, state: .absent) }
        #expect(file.heldAttendance(at: date("2026-11-02 12:59")).map(\.sessionId) == [held.id])
        #expect(file.heldAttendance(at: date("2026-11-02 13:00")).count == 2)
    }

    @Test func aDeletedNoteLeavesTheSessionsThatUsedIt() {
        let gone = UUID(), kept = UUID()
        var a = Session(device: device, at: .now, week: 8, date: date("2026-10-19 13:00"))
        a.roughNoteId = gone
        a.reviewNoteId = kept
        var b = Session(device: device, at: .now, week: 8, date: date("2026-10-21 13:00"))
        b.reviewNoteId = gone
        var file = CourseFile(course: courses[0], sessions: [a, b])
        file.forgetNote(gone)
        #expect(file.sessions.map(\.roughNoteId) == [nil, nil])
        #expect(file.sessions.map(\.reviewNoteId) == [kept, nil])

        // Linked as b's review note, it replaces b's and leaves a, where it was the rough note.
        file.sessions[0].roughNoteId = gone
        file.linkNote(gone, to: b.id, as: .review)
        #expect(file.sessions.map(\.roughNoteId) == [nil, nil])
        #expect(file.sessions.map(\.reviewNoteId) == [kept, gone])
        file.linkNote(gone, to: nil, as: .review)
        #expect(file.sessions.map(\.reviewNoteId) == [kept, nil])
    }

    @Test func sessionEndsWhereItsWeeklySlotEnds() {
        let slot = ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 14 * 60 + 15)
        let monday = Session(device: device, at: .now, week: 9, date: date("2026-10-26 13:00"))
        #expect(monday.end(schedule: [slot], calendar: calendar) == date("2026-10-26 14:15"))
        let midnight = Session(device: device, at: .now, week: 9, date: date("2026-10-26 00:00"))
        #expect(midnight.end(schedule: [slot], calendar: calendar) == nil)
    }

    @Test func aClassWithNoEndRunsTheCoursesUsualLengthElseTheSettings() {
        // A chemistry lab meets for two hours: a makeup off the timetable runs two hours too.
        let lab = [ClassTime(weekday: 2, startMinute: 13 * 60, endMinute: 15 * 60), ClassTime(weekday: 4, startMinute: 13 * 60, endMinute: 15 * 60),
                   ClassTime(weekday: 5, startMinute: 9 * 60, endMinute: 9 * 60 + 50)]
        #expect(lab.usualMinutes == 120)
        #expect([ClassTime(weekday: 1, startMinute: 600, endMinute: 650), ClassTime(weekday: 3, startMinute: 600, endMinute: 680)].usualMinutes == 80)
        #expect([ClassTime]().usualMinutes == nil)

        let makeup = Session(device: device, at: .now, week: 10, date: date("2026-11-04 19:00"))
        #expect(makeup.expectedEnd(schedule: lab, classMinutes: 75, calendar: calendar) == date("2026-11-04 21:00"))
        // No class times at all, as at a school abroad before they're entered: the settings say.
        #expect(makeup.expectedEnd(schedule: [], classMinutes: 80, calendar: calendar) == date("2026-11-04 20:20"))
    }

    @Test func aMakeupKeepsItsOwnEndAndASlotEndIsNotStoredTwice() {
        let slot = ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 14 * 60 + 15)
        var makeup = Session(device: device, at: .now, week: 10, date: date("2026-11-04 21:00"))
        makeup.setEnd(date("2026-11-04 22:15"), schedule: [slot], calendar: calendar)
        #expect(makeup.end(schedule: [slot], calendar: calendar) == date("2026-11-04 22:15"))

        // The slot already says when a Monday 13:00 class ends, so changing the class times later still moves it.
        var monday = Session(device: device, at: .now, week: 9, date: date("2026-10-26 13:00"))
        monday.setEnd(date("2026-10-26 14:15"), schedule: [slot], calendar: calendar)
        #expect(monday.end == nil)
        monday.setEnd(date("2026-10-26 14:45"), schedule: [slot], calendar: calendar)
        #expect(monday.end(schedule: [slot], calendar: calendar) == date("2026-10-26 14:45"))
    }

    @Test func aSessionTakesItsSlotsLinkUnlessItHasItsOwn() {
        let slot = ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 14 * 60 + 15, link: "https://zoom.us/j/111")
        var s = Session(device: device, at: .now, week: 9, date: date("2026-10-26 13:00"))
        #expect(s.link(schedule: [slot], calendar: calendar) == URL(string: "https://zoom.us/j/111"))
        s.link = "meet.google.com/abc-defg-hij"
        #expect(s.link(schedule: [slot], calendar: calendar) == URL(string: "https://meet.google.com/abc-defg-hij"))
        let offSlot = Session(device: device, at: .now, week: 9, date: date("2026-10-26 21:00"))
        #expect(offSlot.link(schedule: [slot], calendar: calendar) == nil)
    }

    @Test func onlyAWebAddressIsAMeetingLink() {
        #expect(OnlineLink.url("  https://us06web.zoom.us/j/88470108867?pwd=abc.1 \n") == URL(string: "https://us06web.zoom.us/j/88470108867?pwd=abc.1"))
        #expect(OnlineLink.url("zoom.us/j/123") == URL(string: "https://zoom.us/j/123"))
        for bad in ["", "884 7010 8867", "813643", "ftp://zoom.us/j/1", "회의 링크", "localhost"] { #expect(OnlineLink.url(bad) == nil, "\(bad)") }
    }

    @Test func aZoomLinkOpensTheZoomApp() throws {
        let web = try #require(URL(string: "https://us06web.zoom.us/j/88470108867?pwd=NrYC.1"))
        #expect(OnlineLink.appURL(web)?.absoluteString == "zoommtg://zoom.us/join?action=join&confno=88470108867&pwd=NrYC.1")
        #expect(OnlineLink.appURL(try #require(URL(string: "https://zoom.us/j/123")))?.absoluteString == "zoommtg://zoom.us/join?action=join&confno=123")
        #expect(OnlineLink.appURL(try #require(URL(string: "https://us06web.zoom.us/launch/jc/884"))) == nil)
        #expect(OnlineLink.appURL(try #require(URL(string: "https://meet.google.com/abc"))) == nil)
        #expect(OnlineLink.appURL(try #require(URL(string: "https://notzoom.us/j/123"))) == nil)
    }

    /// A makeup set up before the class earlier that week used to take 10주차-2 and push the class to 10주차-3.
    @Test func namesFollowTheDatesNotTheOrderMade() {
        let makeup = Session(device: device, at: date("2026-11-01 09:00"), week: 10, date: date("2026-11-04 21:00"))
        let tuesday = Session(device: device, at: date("2026-11-03 10:00"), week: 10, date: date("2026-11-03 10:30"))
        var file = CourseFile(course: courses[0], sessions: [makeup, tuesday])
        #expect([tuesday, makeup].map(file.name(of:)) == ["10주차-1", "10주차-2"])
        // A session not yet in the file is named where its date puts it.
        let monday = Session(device: device, at: .now, week: 10, date: date("2026-11-02 10:30"))
        #expect(monday.name(among: file.sessions) == "10주차-1")
        file.sessions.removeAll { $0.id == tuesday.id }
        #expect(file.name(of: makeup) == "10주차-1")
    }

    @Test func linkListsLeaveOutCancelledClassesUnlessLinked() {
        let held = Session(device: device, at: .now, week: 10, date: date("2026-11-03 10:30"))
        var cancelled = Session(device: device, at: .now, week: 10, date: date("2026-11-05 10:30"))
        cancelled.isCancelled = true
        let file = CourseFile(course: courses[0], sessions: [cancelled, held])
        #expect(file.linkableSessions { _ in false }.map(\.id) == [held.id])
        #expect(file.linkableSessions { $0.id == cancelled.id }.map(\.id) == [held.id, cancelled.id])
    }

    @Test func titleIsTheDayAndWhatTheClassCovered() {
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-03 10:30"))
        var file = CourseFile(course: courses[0], sessions: [s])
        #expect(file.title(of: s, calendar: calendar) == "11/3(화)")
        let parent = Unit(device: device, at: .now, title: "행복", order: 1)
        var child = Unit(device: device, at: .now, title: "습관", order: 1, parentId: parent.id)
        child.sessionIds = [s.id]
        file.units = [parent, child]
        #expect(file.title(of: s, calendar: calendar) == "11/3(화): 습관")
        s.topic = "행복에도 습관이 무섭다"
        #expect(file.title(of: s, calendar: calendar) == "11/3(화): 행복에도 습관이 무섭다")
    }

    @Test func aSessionNoteIsNamedByTheDayAndWhatTheClassCovered() {
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-05 10:30"))
        var file = CourseFile(course: courses[0], sessions: [s])
        #expect(file.noteTitle(for: s, kind: .rough, calendar: calendar) == "11-05(목)")
        #expect(file.noteTitle(for: s, kind: .review, calendar: calendar) == "11-05(목) 정리")

        let parent = Unit(device: device, at: .now, title: "Transport layer", order: 1)
        var child = Unit(device: device, at: .now, title: "Reliable data transfer", order: 1, parentId: parent.id)
        child.sessionIds = [s.id]
        file.units = [parent, child]
        #expect(file.noteTitle(for: s, kind: .rough, calendar: calendar) == "11-05(목) Reliable data transfer")

        s.topic = "Principles of reliable data transfer"
        file.sessions = [s]
        #expect(file.noteTitle(for: s, kind: .rough, calendar: calendar) == "11-05(목) Principles of reliable data transfer")
        #expect(file.noteTitle(for: s, kind: .review, calendar: calendar) == "11-05(목) Principles of reliable data transfer 정리")
    }

    @Test func aSessionNoteNameHoldsNoPathOrLinkCharacters() {
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-03 10:30"))
        s.topic = "..TCP: flow/congestion [ch. 3] #1"
        let file = CourseFile(course: courses[0], sessions: [s])
        #expect(file.noteTitle(for: s, kind: .rough, calendar: calendar) == "11-03(화) TCP flow-congestion ch. 3 1")
    }

    @Test func aLongSubjectIsCutAtAWord() {
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-03 10:30"))
        s.topic = "Principles of reliable data transfer with pipelined protocols, Go-Back-N and selective repeat"
        let file = CourseFile(course: courses[0], sessions: [s])
        let title = file.noteTitle(for: s, kind: .review, calendar: calendar)
        #expect(title == "11-03(화) Principles of reliable data transfer with pipelined 정리")

        s.topic = String(repeating: "가", count: 100)
        let unbroken = CourseFile(course: courses[0], sessions: [s]).noteTitle(for: s, kind: .rough, calendar: calendar)
        #expect(unbroken == "11-03(화) " + String(repeating: "가", count: 60))
    }

    /// The name is the day the class was held, as its title is, not the study day the 4 a.m. boundary would give.
    @Test func aLateClassIsNamedByItsCalendarDay() {
        let s = Session(device: device, at: .now, week: 10, date: date("2026-11-06 01:00"))
        let file = CourseFile(course: courses[0], sessions: [s])
        #expect(file.noteTitle(for: s, kind: .rough, calendar: calendar) == "11-06(금)")
    }

    @Test func movingASessionNamesItByItsNewDate() {
        let start = LocalDate(year: 2026, month: 9, day: 1)!
        let a = Session(device: device, at: .now, week: 10, date: date("2026-11-03 10:30"))
        var b = Session(device: device, at: .now, week: 10, date: date("2026-11-04 21:00"))
        b.end = date("2026-11-04 22:15")
        let c = Session(device: device, at: .now, week: 11, date: date("2026-11-10 10:30"))
        var file = CourseFile(course: courses[0], sessions: [a, b, c])

        // Within its week it keeps its name; its own end moves with it.
        file.reschedule(b.id, to: date("2026-11-05 20:00"), termStart: start, calendar: calendar)
        #expect(file.sessions[1].week == 10 && file.name(of: file.sessions[1]) == "10주차-2")
        #expect(file.sessions[1].end == date("2026-11-05 21:15"))

        #expect(file.week(of: date("2026-11-12 20:00"), moving: b.id, termStart: start, calendar: calendar) == 11)
        file.reschedule(b.id, to: date("2026-11-12 20:00"), termStart: start, calendar: calendar)
        #expect(file.sessions[1].week == 11 && file.name(of: file.sessions[1]) == "11주차-2")
        // Moved before the class that week, it takes the first name.
        file.reschedule(b.id, to: date("2026-11-09 20:00"), termStart: start, calendar: calendar)
        #expect(file.name(of: file.sessions[1]) == "11주차-1" && file.name(of: file.sessions[2]) == "11주차-2")
    }

    @Test func aSessionEndingBeforeItStartsOrABadLinkIsRefused() {
        func rules(_ s: Session) -> Set<String> {
            Set(CourseFile.model.violations(in: CourseFile(course: courses[0], sessions: [s])).map(\.rule.name))
        }
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-04 21:00"))
        s.end = date("2026-11-04 20:00")
        #expect(rules(s).contains("Session.time"))
        s.end = nil
        s.link = "813643"
        #expect(rules(s).contains("Session.link"))
        s.link = "https://zoom.us/j/1"
        #expect(rules(s).isDisjoint(with: ["Session.time", "Session.link"]))
    }

    /// The session holds a note's link alone: it names a note of its slot's kind, and no rough note has two sessions.
    /// A review note may cover several.
    @Test func aRoughNoteHasOneSession() {
        var s = Session(device: device, at: .now, week: 10, date: date("2026-11-04 21:00"))
        var other = Session(device: device, at: .now, week: 11, date: date("2026-11-11 21:00"))
        let review = NoteEntry(id: UUID(), device: device, at: .now, path: "Notes/a.md", meta: NoteMeta(id: nil, kind: .review))
        let free = NoteEntry(id: UUID(), device: device, at: .now, path: "Notes/b.md", meta: NoteMeta(id: nil))
        let rough = NoteEntry(id: UUID(), device: device, at: .now, path: "Notes/c.md", meta: NoteMeta(id: nil, kind: .rough))
        func rules(_ sessions: [Session], _ notes: [NoteEntry] = [review, free, rough]) -> Set<String> {
            var file = CourseFile(course: courses[0], sessions: sessions)
            file.notes = notes
            return Set(CourseFile.model.violations(in: file).map(\.rule.name))
        }
        s.reviewNoteId = review.id
        other.reviewNoteId = review.id
        #expect(rules([s, other]).isDisjoint(with: ["NoteEntry.session", "Session.noteKind", "NoteEntry.units"]))
        s.roughNoteId = rough.id
        other.roughNoteId = rough.id
        #expect(rules([s, other]).contains("NoteEntry.session"))
        other.roughNoteId = nil
        other.reviewNoteId = free.id
        #expect(rules([s, other]).contains("Session.noteKind"))
        var stale = review
        stale.unitIds = [UUID()]
        #expect(rules([s], [stale]).contains("NoteEntry.units"))
    }

    // MARK: Quick add

    let gsCode: CourseCode
    let courses: [Course]

    init() {
        gsCode = CourseCode(device: device, at: .now, prefix: "EC")
        courses = [Course(device: device, at: .now, title: "선형대수학과 응용", number: "2004-02"),
                   Course(device: device, at: .now, title: "그래프 이론", codes: [gsCode.id], number: "4207-01")]
    }

    @Test func parsesCourseTitleAndWeekday() {
        let now = date("2026-10-22 15:00")  // Thursday
        let r = QuickAdd.parse("선대 HW5 금 23:59", courses: courses, now: now, calendar: calendar)
        #expect(r.courseId == courses[0].id)
        #expect(r.title == "HW5")
        #expect(r.due == date("2026-10-23 23:59"))
        #expect(r.dueRanges.map { String("선대 HW5 금 23:59"[$0]) } == ["금 23:59"])
    }

    @Test func weeklyAssignmentsParseAndContinueOnceHandedIn() {
        let now = date("2026-10-26 12:00")  // Monday
        let line = "보고서 제출 매주 금요일 23:59"
        let r = QuickAdd.parse(line, courses: [], now: now, calendar: calendar)
        #expect(r.title == "보고서 제출" && r.repeats == .weekly && r.due == date("2026-10-30 23:59"))
        #expect(r.dueRanges.map { String(line[$0]) } == ["매주 금요일 23:59"])

        var first = Assignment(device: device, at: now, title: "보고서 제출", due: r.due)
        first.repeats = .weekly
        var file = CourseFile(course: courses[0], assignments: [first])
        let end = date("2026-11-06 23:59")
        file.continueRepeating(first.id, until: end, calendar: calendar, device: device, now: now)
        #expect(file.assignments.count == 1)  // still open
        file.assignments[0].status = .submitted
        file.continueRepeating(first.id, until: end, calendar: calendar, device: device, now: now)
        file.continueRepeating(first.id, until: end, calendar: calendar, device: device, now: now)
        #expect(file.assignments.map(\.due) == [date("2026-10-30 23:59"), date("2026-11-06 23:59")])
        #expect(file.assignments[1].repeats == .weekly && file.assignments[1].status == .todo)
        // Past the term's end nothing more is made.
        file.assignments[1].status = .submitted
        file.continueRepeating(file.assignments[1].id, until: end, calendar: calendar, device: device, now: now)
        #expect(file.assignments.count == 2)
    }

    @Test func sameWeekdayAfterTheTimeMeansNextWeek() {
        let now = date("2026-10-23 23:59")  // Friday, deadline time reached
        #expect(QuickAdd.parse("HW5 금", courses: [], now: now, calendar: calendar).due == date("2026-10-30 23:59"))
        #expect(QuickAdd.parse("HW5 금 23:59", courses: [], now: date("2026-10-23 12:00"), calendar: calendar).due == date("2026-10-23 23:59"))
    }

    @Test func codesRelativeDaysAndDates() {
        let now = date("2026-10-22 15:00")
        let byCode = QuickAdd.parse("EC4207 Slow Problem 2 내일", courses: courses, codes: [gsCode], now: now, calendar: calendar)
        #expect(byCode.courseId == courses[1].id && byCode.title == "Slow Problem 2" && byCode.due == date("2026-10-23 23:59"))

        let past = QuickAdd.parse("보고서 3/2 9:00", courses: [], now: now, calendar: calendar)
        #expect(past.due == date("2027-03-02 09:00"))

        let fixed = QuickAdd.parse("퀴즈 준비", courses: courses, fixedCourse: courses[1].id, now: now, calendar: calendar)
        #expect(fixed.courseId == courses[1].id && fixed.title == "퀴즈 준비" && fixed.due == nil)
    }

    /// Phrases only Apple's detector reads. It works against the real clock, so expectations are relative to it.
    @Test func koreanPhrasesFromTheDetector() {
        let now = Date.now
        func due(_ line: String) -> Date? { QuickAdd.parse(line, courses: [], now: now, calendar: calendar).due }
        func at(days: Int, _ h: Int, _ m: Int) -> Date {
            calendar.date(bySettingHour: h, minute: m, second: 0, of: calendar.date(byAdding: .day, value: days, to: now)!)!
        }
        #expect(due("보고서 모레 오후 3시") == at(days: 2, 15, 0))
        #expect(due("보고서 오늘 밤 11시") == at(days: 0, 23, 0))
        #expect(due("보고서 내일 자정") == at(days: 2, 0, 0))
        let r = QuickAdd.parse("HW5 다음 주 금요일", courses: [], now: now, calendar: calendar)
        #expect(r.title == "HW5" && r.due.map { calendar.component(.weekday, from: $0) } == 6)
        #expect(r.due.map { calendar.component(.hour, from: $0) } == 23)
        let m = QuickAdd.parse("PS 3 2번 11월 3일 오후 11시 59분", courses: [], now: now, calendar: calendar)
        #expect(m.title == "PS 3 2번" && m.due.map { calendar.dateComponents([.month, .day, .hour, .minute], from: $0) }
                == DateComponents(month: 11, day: 3, hour: 23, minute: 59))
        #expect(QuickAdd.parse("Slow Problem 2 Chapter 5 1-10", courses: [], now: now, calendar: calendar).due == nil)
    }

    @Test func courseAnywhereWithAParticle() {
        let now = date("2026-10-22 15:00")
        let r = QuickAdd.parse("내일 7시 선형대수학에다 HW5", courses: courses, now: now, calendar: calendar)
        #expect(r.courseId == courses[0].id && r.title == "HW5" && r.due == date("2026-10-23 19:00"))
        // Past the first word, a short or numbered word is the title, not an abbreviation.
        #expect(QuickAdd.parse("보고서 선 HW5", courses: courses, now: now, calendar: calendar).courseId == nil)
    }

    @Test func ambiguousAbbreviationMatchesNothing() {
        let two = courses + [Course(device: device, at: .now, title: "선형대수학 심화")]
        #expect(QuickAdd.parse("선대 HW1", courses: two, now: .now, calendar: calendar).courseId == nil)
    }

    // MARK: Folder names

    @Test func standardFolderNames() {
        #expect(AssignmentKind.parse(title: "HW5")?.kind.folderName(5) == "HW05")
        #expect(AssignmentKind.parse(title: "lab 3 report") .map { $0.kind.folderName($0.number) } == "Lab03")
        #expect(AssignmentKind.parse(title: "Slow Problem 2") == nil)
        #expect(StandardLayout.isExamFolderName("Quiz2") && !StandardLayout.isExamFolderName("Quiz0") && !StandardLayout.isExamFolderName("Quiz"))
    }
}

@Test func assignmentFoldersWithoutAnAssignmentAreListed() {
    let existing = [Assignment(device: UUID(), at: .now, title: "HW 1"), Assignment(device: UUID(), at: .now, title: "기말 프로젝트")]
    #expect(AssignmentKind.unmatchedFolders(["HW02", "HW01", "SP01", "기말 프로젝트"], assignments: existing) == ["HW02", "SP01"])
}

struct AssignmentFilesTests {
    let device = UUID()

    @Test func submissionNamesAreRecognized() {
        #expect(AssignmentFiles.guessKind(fileName: "HW3-5070류현승.pdf") == .submission)
        #expect(AssignmentFiles.guessKind(fileName: "SP1_류현승.pdf") == .submission)
        #expect(AssignmentFiles.guessKind(fileName: "26h3.pdf") == .problem)
        #expect(AssignmentFiles.guessKind(fileName: "HW3.pdf") == .problem)
    }

    @Test func folderFilesAndSubmittedSuggestion() {
        var hw = Assignment(device: device, at: .now, title: "HW 3")
        let files = [
            Material(device: device, at: .now, path: "Assignments/HW03/26h3.pdf", status: .classified),
            Material(device: device, at: .now, path: "Assignments/HW03/HW3-5070류현승.pdf", status: .classified),
            Material(device: device, at: .now, path: "Assignments/HW04/26h4.pdf", status: .classified),
        ]
        let mine = AssignmentFiles.materials(of: hw, in: files)
        #expect(mine.count == 2)
        #expect(AssignmentFiles.suggestsSubmitted(hw, files: mine))
        hw.status = .submitted
        #expect(!AssignmentFiles.suggestsSubmitted(hw, files: mine))
    }

    @Test func dueStates() {
        let cal = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(DueState(due: nil, now: now, calendar: cal) == .none)
        #expect(DueState(due: now.addingTimeInterval(-3 * 86400), now: now, calendar: cal) == .overdue(days: 3))
        #expect(DueState(due: now.addingTimeInterval(5 * 3600 + 60), now: now, calendar: cal) == .hours(6))
        if case .days(let d) = DueState(due: now.addingTimeInterval(3 * 86400), now: now, calendar: cal) { #expect(d == 3) } else { Issue.record("expected days") }
    }

    @Test func dueUrgencyCountsStudyDaysAcrossTheBoundary() {
        let settings = Settings()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        #expect(settings.dayBoundaryMinutes == 4 * 60)
        func at(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        func urgency(_ due: Date) -> DueUrgency { DueUrgency(due: due, now: at(29, 2), settings: settings, calendar: calendar) }
        // At 02:00 on the 29th the study day is still the 28th.
        #expect(settings.studyDays(from: at(29, 2), until: at(29, 3), calendar: calendar) == 0)
        #expect(settings.studyDays(from: at(29, 2), until: at(29, 5), calendar: calendar) == 1)
        #expect(urgency(at(29, 3)) == .urgent)
        #expect(urgency(at(30, 2)) == .urgent)
        #expect(urgency(at(30, 5)) == .soon)
        #expect(urgency(at(35, 3)) == .soon)
        #expect(urgency(at(35, 5)) == .later)
    }
}
