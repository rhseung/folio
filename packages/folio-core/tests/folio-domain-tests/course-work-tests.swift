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
        var cancelled = Session(device: device, at: .now, week: 9, index: 1, date: date("2026-10-26 13:00"))
        cancelled.isCancelled = true
        let dateOnly = Session(device: device, at: .now, week: 9, index: 2, date: date("2026-10-28 00:00"))
        let s = SessionPlanner.suggestion(schedule: monWed, sessions: [cancelled, dateOnly], from: nil, to: nil, now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(s?.date == date("2026-11-02 13:00"))
    }

    /// 2026 fall starts Monday 8/31, so 10/19 opens week 8, the default midterm week.
    @Test func examWeeksAndExamTimesHoldNoLectures() {
        let fall = Semester(device: device, at: .now, year: 2026, term: .fall, start: LocalDate("2026-08-31"), end: LocalDate("2026-12-18"))
        #expect(fall.examWeeks == [8, 16])
        let skipped = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: fall.start, to: fall.end, examWeeks: fall.examWeeks,
                                                now: date("2026-10-19 09:00"), calendar: calendar)
        #expect(skipped?.date == date("2026-10-26 13:00"))
        // A midterm in Monday's class time outside the exam week takes that class; Wednesday's still comes.
        let exam = DateInterval(start: date("2026-10-26 13:00"), end: date("2026-10-26 15:00"))
        let moved = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: fall.start, to: fall.end, examWeeks: fall.examWeeks,
                                              exams: [exam], now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(moved?.date == date("2026-10-28 13:00"))
        #expect(Semester(device: device, at: .now, year: 2026, term: .summer).examWeeks.isEmpty)
    }

    @Test func noSuggestionOutsideTheTerm() {
        let ended = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: nil, to: LocalDate("2026-10-27"), now: date("2026-10-26 15:00"), calendar: calendar)
        #expect(ended == nil)
        let before = SessionPlanner.suggestion(schedule: monWed, sessions: [], from: LocalDate("2026-10-28"), to: nil, now: date("2026-10-26 09:00"), calendar: calendar)
        #expect(before?.date == date("2026-10-28 13:00"))
    }

    @Test func newSessionsCountWeeksFromTheTermStartAndGoLastInTheWeek() {
        // Term starts Wednesday 2026-09-02: that week is 1, so 2026-10-26 is 9주차.
        let first = SessionPlanner.session(at: date("2026-10-26 13:00"), sessions: [], termStart: LocalDate("2026-09-02"),
                                           calendar: calendar, device: device, now: .now)
        #expect(first.week == 9 && first.index == 1)
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
        func at(_ s: String) -> Session { Session(device: device, at: .now, week: 9, index: 1, date: date(s)) }
        let past = at("2026-10-19 13:00"), empty = at("2026-11-02 13:00"), noted = at("2026-11-04 13:00"), unitLinked = at("2026-11-09 13:00")
        var topic = at("2026-11-11 13:00"); topic.topic = "행렬식"
        var cancelled = Session(device: device, at: .now, week: 10, index: 1, date: date("2026-11-16 13:00"))
        cancelled.isCancelled = true
        var unit = Unit(device: device, at: .now, title: "고윳값", order: 1)
        unit.sessionIds = [unitLinked.id]
        let file = CourseFile(course: courses[0], units: [unit], sessions: [past, empty, noted, unitLinked, topic, cancelled])
        #expect(file.untouchedFutureSessions(now: now, notedSessions: [noted.id]).map(\.id) == [empty.id])
    }

    /// A past session can be deleted too, as long as nothing points at it.
    @Test func onlyAnUnlinkedSessionIsDeletable() {
        let held = Session(device: device, at: .now, week: 8, index: 1, date: date("2026-10-19 13:00"))
        let attended = Session(device: device, at: .now, week: 8, index: 2, date: date("2026-10-21 13:00"))
        var file = CourseFile(course: courses[0], sessions: [held, attended])
        file.attendance = [Attendance(device: device, at: .now, sessionId: attended.id, state: .late)]
        #expect(file.isUnlinked(held, notedSessions: []))
        #expect(!file.isUnlinked(held, notedSessions: [held.id]))
        #expect(!file.isUnlinked(attended, notedSessions: []))
    }

    @Test func anAbsenceMarkedAheadCountsFromItsClass() {
        let held = Session(device: device, at: .now, week: 9, index: 1, date: date("2026-10-26 13:00"))
        let ahead = Session(device: device, at: .now, week: 10, index: 1, date: date("2026-11-02 13:00"))
        var file = CourseFile(course: courses[0], sessions: [held, ahead])
        file.attendance = [held, ahead].map { Attendance(device: device, at: .now, sessionId: $0.id, state: .absent) }
        #expect(file.heldAttendance(at: date("2026-11-02 12:59")).map(\.sessionId) == [held.id])
        #expect(file.heldAttendance(at: date("2026-11-02 13:00")).count == 2)
    }

    @Test func aDeletedNoteLeavesTheSessionsThatUsedIt() {
        let gone = UUID(), kept = UUID()
        var a = Session(device: device, at: .now, week: 8, index: 1, date: date("2026-10-19 13:00"))
        a.roughNoteId = gone
        a.reviewNoteId = kept
        var b = Session(device: device, at: .now, week: 8, index: 2, date: date("2026-10-21 13:00"))
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
        let monday = Session(device: device, at: .now, week: 9, index: 1, date: date("2026-10-26 13:00"))
        #expect(monday.end(schedule: [slot], calendar: calendar) == date("2026-10-26 14:15"))
        let midnight = Session(device: device, at: .now, week: 9, index: 1, date: date("2026-10-26 00:00"))
        #expect(midnight.end(schedule: [slot], calendar: calendar) == nil)
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
        #expect(ExamKind.quiz.folderName(number: 2) == "Quiz2")
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
}
