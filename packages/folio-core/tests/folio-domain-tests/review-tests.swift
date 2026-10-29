import FolioDomain
import Foundation
import Testing

struct DayBoundaryTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// CLAUDE.md: check just before and just after the 04:00 boundary.
    @Test func streakCountsBackFromTodayOrYesterday() {
        let today = LocalDate(year: 2026, month: 10, day: 24)!
        let days: Set<LocalDate> = [today.adding(days: -1), today.adding(days: -2), today.adding(days: -4)]
        #expect(ReviewStreak.days(days, today: today) == 2)
        #expect(ReviewStreak.days(days.union([today]), today: today) == 3)
        #expect(ReviewStreak.days([today.adding(days: -2)], today: today) == 0)
    }

    @Test func fourAMBoundary() {
        let s = Settings()
        #expect(s.studyDay(of: at(23, 3, 59), calendar: calendar) == LocalDate("2026-10-22"))
        #expect(s.studyDay(of: at(23, 4, 0), calendar: calendar) == LocalDate("2026-10-23"))
        #expect(s.studyDay(of: at(22, 23, 59), calendar: calendar) == LocalDate("2026-10-22"))
    }

    @Test func boundaryIsConfigurable() {
        let s = Settings(dayBoundaryMinutes: 0)
        #expect(s.studyDay(of: at(23, 0, 0), calendar: calendar) == LocalDate("2026-10-23"))
    }

    @Test func missingSettingsKeysFallBackToDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"review":{"dailyLimit":3}}"#.utf8))
        #expect(s.dayBoundaryMinutes == 240 && s.review.dailyLimit == 3 && s.review.intervals == [1, 3, 7, 14, 30])
    }

    @Test func emptyIntervalsFallBackAndStepsPastTheEndKeepTheLast() throws {
        let s = try JSONDecoder().decode(ReviewSettings.self, from: Data(#"{"intervals":[0]}"#.utf8))
        #expect(s.intervals == [1, 3, 7, 14, 30])
        #expect(s.interval(atStep: 9) == 30 && s.interval(atStep: 0) == 1)
    }

    @Test func studyTimeMergesOverlapsAndUsesStudyDay() {
        let course = UUID()
        let sessions = [
            StudySessionEvent(courseId: course, start: at(23, 1, 0), end: at(23, 2, 0), screen: "note"),   // Mac
            StudySessionEvent(courseId: course, start: at(23, 1, 30), end: at(23, 2, 30), screen: "ink"),  // iPad, overlaps
            StudySessionEvent(courseId: course, start: at(23, 10, 0), end: at(23, 10, 30), screen: "quiz"),
        ]
        let perDay = StudyTime.perDay(sessions, settings: Settings(), calendar: calendar)
        #expect(perDay == [LocalDate("2026-10-22")!: 90 * 60, LocalDate("2026-10-23")!: 30 * 60])
    }
}

struct ReviewSchedulerTests {
    let settings = ReviewSettings()
    let unit = UUID()
    func d(_ s: String) -> LocalDate { LocalDate(s)! }

    func state(_ reviews: [(String, ReviewResult)], wrong: [String] = [], exams: [String] = [], plan: Bool = false, note: Bool = false) -> ReviewState {
        let input = UnitReviewInput(unitId: unit, startDay: d("2026-10-01"), needsReviewNote: note,
                                    reviews: reviews.map { (d($0.0), $0.1) }, wrongCardDays: wrong.map(d), examDays: exams.map(d), inExamPlan: plan)
        return ReviewScheduler.state(of: input, settings: settings, today: d("2026-10-22"))
    }

    @Test func startsOneDayAfterTheReviewNote() {
        #expect(state([]).due == d("2026-10-02"))
    }

    @Test func withoutReviewNoteWritingItComesFirst() {
        let s = state([], note: true)
        #expect(s.due == d("2026-10-01") && s.writeNoteFirst)
        #expect(!state([("2026-10-01", .good)], note: true).writeNoteFirst)
    }

    @Test func resultsMoveTheStep() {
        // good: 1 → 3 days; easy skips a step; hard repeats; again resets to 1 day.
        #expect(state([("2026-10-02", .good)]).due == d("2026-10-05"))
        #expect(state([("2026-10-02", .easy)]).due == d("2026-10-09"))
        #expect(state([("2026-10-02", .good), ("2026-10-05", .hard)]).due == d("2026-10-08"))
        #expect(state([("2026-10-02", .good), ("2026-10-05", .again)]).due == d("2026-10-06"))
    }

    @Test func settlesAfterTwoPassesAtThirtyDays() {
        let climb: [(String, ReviewResult)] = [("2026-10-02", .easy), ("2026-10-09", .good), ("2026-10-23", .good)]
        #expect(state(climb).step == 4 && !state(climb).settled)
        let once = state(climb + [("2026-11-22", .good)])
        #expect(!once.settled && once.due == d("2026-12-22"))
        let twice = state(climb + [("2026-11-22", .good), ("2026-12-22", .easy)])
        #expect(twice.settled && twice.due == nil)
        #expect(state(climb + [("2026-11-22", .good), ("2026-12-22", .easy)], plan: true).due != nil)
    }

    @Test func skipSettlesUntilAWrongCardOrAnExamPlan() {
        let skipped = state([("2026-10-20", .skip)], note: true)
        #expect(skipped.settled && skipped.due == nil && !skipped.writeNoteFirst)
        #expect(state([("2026-10-20", .skip)], plan: true).due != nil)
        let wrong = state([("2026-10-20", .skip)], wrong: ["2026-10-21"])
        #expect(!wrong.settled && wrong.due == d("2026-10-22"))
    }

    @Test func wrongCardPullsReviewToTomorrowAndDropsAStep() {
        let s = state([("2026-10-02", .good), ("2026-10-05", .good)], wrong: ["2026-10-07"])
        #expect(s.due == d("2026-10-08") && s.step == 1)
    }

    @Test func examLimitsIntervals() {
        // Six days before the exam (inside the 7-day window) a 14-day interval is capped to half the days left.
        let s = state([("2026-10-02", .easy), ("2026-10-14", .good)], exams: ["2026-10-20"])
        #expect(s.due == d("2026-10-17"))
        // Outside the window the review still may not pass the day before the exam.
        let far = state([("2026-10-02", .easy), ("2026-10-09", .good)], exams: ["2026-10-20"])
        #expect(far.due == d("2026-10-19"))
    }

    @Test func queueOrdersByPriorityAndDefersOverflow() {
        let a = UUID(), b = UUID(), c = UUID()
        let today = d("2026-10-22")
        let inputs = [
            UnitReviewInput(unitId: a, startDay: d("2026-10-01")),
            UnitReviewInput(unitId: b, startDay: d("2026-10-01"), examDays: [d("2026-10-24")]),
            UnitReviewInput(unitId: c, startDay: d("2026-10-01"), quizAccuracy: 0.2, openWrongCards: 5),
        ]
        let states = [
            ReviewState(unitId: a, step: 0, due: d("2026-10-20"), settled: false, writeNoteFirst: false),  // 2 days over a 1-day interval
            ReviewState(unitId: b, step: 3, due: d("2026-10-22"), settled: false, writeNoteFirst: false),  // exam in 2 days
            ReviewState(unitId: c, step: 2, due: d("2026-10-25"), settled: false, writeNoteFirst: false),  // not due yet
        ]
        var limited = settings
        limited.dailyLimit = 1
        let q = ReviewScheduler.queue(states, inputs: inputs, settings: limited, today: today)
        #expect(q.map(\.unitId) == [a, b])
        #expect(q[0].overdueDays == 2 && q[0].deferred == nil)
        #expect(q[1].deferred == .dailyLimit)
    }
}

struct TodayTests {
    let device = UUID()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func collectsTodayAcrossCourses() {
        let now = at(23, 2, 0)  // 02:00 Friday → study day is Thursday the 22nd
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.exams = [Exam(device: device, at: now, kind: .midterm, title: "Midterm", start: at(27, 19))]
        var late = Assignment(device: device, at: now, title: "HW5", due: at(23, 3, 0))     // still "today" in study time
        late.status = .todo
        let nextWeek = Assignment(device: device, at: now, title: "HW6", due: at(28, 23, 59))
        let gone = Assignment(device: device, at: now, title: "HW4", due: at(23, 1, 0))     // already passed
        let project = Assignment(device: device, at: now, title: "Project", due: at(31, 23, 59))  // past the week
        file.assignments = [late, nextWeek, gone, project]
        var written = Session(device: device, at: now, week: 7, index: 1, date: at(20, 10))
        written.reviewNoteId = UUID()
        file.sessions = [
            written,
            Session(device: device, at: now, week: 7, index: 2, date: at(22, 10)),
            Session(device: device, at: now, week: 7, index: 3, date: at(23, 10)),
        ]

        let t = TodaySummary.build(courses: [file], now: now, settings: Settings(), calendar: calendar)
        #expect(t.studyDay == LocalDate("2026-10-22"))
        #expect(t.exams.first?.dDay == 5)
        #expect(t.deadlines.map(\.assignment.title) == ["HW5", "HW6", "Project"])
        #expect(t.deadlines.first?.isToday == true && t.deadlines.last?.isToday == false)
        #expect(t.classesToday.map { file.name(of: $0.session) } == ["7주차-2"])
        // Today's class is over, so its note is due now; tomorrow's isn't.
        #expect(t.missingReviewNotes.map { file.name(of: $0.session) } == ["7주차-2"])
        file.course.schedule = [ClassTime(weekday: 4, startMinute: 10 * 60, endMinute: 11 * 60 + 15)]
        #expect(TodaySummary.build(courses: [file], now: at(22, 11), settings: Settings(), calendar: calendar).missingReviewNotes.isEmpty)
        #expect(TodaySummary.build(courses: [file], now: at(22, 11, 15), settings: Settings(), calendar: calendar).missingReviewNotes.count == 1)
    }

    @Test func aReviewNoteMadeButNotWrittenStillAsksToBeWritten() throws {
        let now = at(23, 12)
        var session = Session(device: device, at: now, week: 7, index: 1, date: at(20, 10))
        session.reviewNoteId = UUID()
        session.reviewNoteUnfinished = true
        #expect(session.needsReviewNote(at: now))
        // Notes from before the flag, and imported ones, decode as written.
        let written = try JSONEncoder().encode({ var s = session; s.reviewNoteUnfinished = false; return s }())
        #expect(!String(decoding: written, as: UTF8.self).contains("reviewNoteDraft"))
        #expect(try !JSONDecoder().decode(Session.self, from: written).needsReviewNote(at: now))
        var file = CourseFile(course: Course(device: device, at: now, title: "컴파일러"))
        file.sessions = [session]
        file.forgetNote(session.reviewNoteId!)
        #expect(!file.sessions[0].reviewNoteUnfinished && file.sessions[0].needsReviewNote(at: now))
        session.reviewNoteUnfinished = false
        #expect(!session.needsReviewNote(at: now))
    }

    @Test func sessionsNeedingNoReviewAskForNoNoteAndDontRestartUnits() throws {
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "컴파일러"))
        var taught = Session(device: device, at: now, week: 7, index: 1, date: at(20, 10))
        taught.reviewNoteId = UUID()
        var grading = Session(device: device, at: now, week: 7, index: 2, date: at(22, 10))
        grading.skipsReview = true
        file.sessions = [taught, grading]
        var unit = Unit(device: device, at: now, title: "파싱", order: 1)
        unit.sessionIds = [taught.id, grading.id]
        file.units = [unit]

        #expect(!grading.needsReviewNote(at: now))
        #expect(!file.needsReviewNote(grading, at: now))
        var noReviews = file
        noReviews.course.reviews = false
        #expect(file.needsReviewNote(Session(device: device, at: now, week: 7, index: 3, date: at(20, 10)), at: now))
        #expect(!noReviews.needsReviewNote(Session(device: device, at: now, week: 7, index: 3, date: at(20, 10)), at: now))
        #expect(TodaySummary.build(courses: [file], now: now, settings: Settings(), calendar: calendar).missingReviewNotes.isEmpty)
        let input = UnitReviewInput.all(for: file, reviews: [], settings: Settings(), calendar: calendar, now: now)
        #expect(input.first?.startDay == LocalDate("2026-10-20") && input.first?.needsReviewNote == false)
        // Stored only when set, so older files and untouched sessions read the same.
        let json = String(decoding: try JSONEncoder().encode([taught, grading]), as: UTF8.self)
        #expect(json.components(separatedBy: "noReview").count == 2)
    }

    @Test func queueAcrossCoursesNamesEachUnitsCourse() {
        let now = at(23, 12)
        func course(_ title: String, unit: String) -> CourseFile {
            var file = CourseFile(course: Course(device: device, at: now, title: title))
            var s = Session(device: device, at: now, week: 1, index: 1, date: at(10, 10))
            s.reviewNoteId = UUID()
            var u = Unit(device: device, at: now, title: unit, order: 1)
            u.sessionIds = [s.id]
            (file.sessions, file.units) = ([s], [u])
            return file
        }
        let (a, b) = (course("그래프 이론", unit: "매칭"), course("선형대수학", unit: "고윳값"))
        let q = ReviewScheduler.queue(courses: [(a, []), (b, [])], settings: Settings(), calendar: calendar, now: now)
        #expect(Set(q.map(\.unitTitle)) == ["매칭", "고윳값"])
        #expect(q.first { $0.unitTitle == "매칭" }?.courseId == a.course.id)
    }

    @Test func capOneAwayOnlyWhenTheNextAbsenceReachesIt() {
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        file.policy.attendanceCap = [AttendanceCap(absences: 6, maxGrade: UUID())]
        let sessions = (0..<6).map { Session(device: device, at: now, week: 1, index: $0, date: at(1 + $0, 9)) }
        file.sessions = sessions
        file.attendance = sessions.prefix(4).map { Attendance(device: device, at: now, sessionId: $0.id, state: .absent) }
        #expect(file.capOneAway(at: now) == nil)
        file.attendance.append(Attendance(device: device, at: now, sessionId: sessions[4].id, state: .absent))
        #expect(file.capOneAway(at: now)?.absences == 5)
        #expect(StudyTime.label(80 * 60) == "1시간 20분")
    }

    @Test func aHeldClassWithNoUnitIsFlaggedUntilOneIsLinked() {
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        let held = Session(device: device, at: now, week: 9, index: 1, date: at(22, 10))
        var grading = Session(device: device, at: now, week: 9, index: 2, date: at(22, 14))
        grading.skipsReview = true
        let ahead = Session(device: device, at: now, week: 9, index: 3, date: at(24, 10))
        file.sessions = [held, grading, ahead]
        file.units = [Unit(device: device, at: now, title: "고윳값", order: 1)]
        #expect(file.sessions.filter { file.needsUnits($0, at: now) }.map(\.id) == [held.id])
        file.toggle(session: held.id, unit: file.units[0].id)
        #expect(!file.needsUnits(file.sessions[0], at: now))
        #expect(file.units(of: file.sessions[0]).map(\.title) == ["고윳값"])
        var chapter = Unit(device: device, at: now, title: "5장", order: 0)
        file.units[0].parentId = chapter.id
        chapter.sessionIds = [held.id]
        file.units.append(chapter)
        #expect(file.units(of: file.sessions[0]).map(\.title) == ["5장", "고윳값"])
        #expect(UnitTree.deepest(file.units(of: file.sessions[0]), in: file.units).map(\.title) == ["고윳값"])
    }

    @Test func aRecitationIsNumberedLikeAnyClass() {
        var file = CourseFile(course: Course(device: device, at: at(20, 9), title: "선형대수학"))
        file.sessions = [
            Session(device: device, at: at(20, 9), week: 9, index: 1, date: at(20, 14, 30)),
            Session(device: device, at: at(20, 9), week: 9, index: 2, date: at(20, 18, 30)),
            Session(device: device, at: at(20, 9), week: 9, index: 3, date: at(22, 14, 30)),
        ]
        #expect(file.sessions.map { file.name(of: $0) } == ["9주차-1", "9주차-2", "9주차-3"])
    }

    @Test func ongoingClassRunsFromItsStartToItsSlotsEnd() {
        var file = CourseFile(course: Course(device: device, at: at(22, 9), title: "그래프 이론"))
        file.course.schedule = [ClassTime(weekday: 4, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)]  // Thursday
        file.sessions = [Session(device: device, at: at(22, 9), week: 7, index: 1, date: at(22, 10, 30))]
        #expect(TodaySummary.ongoingClass(in: [file], at: at(22, 10, 29), calendar: calendar) == nil)
        let ongoing = TodaySummary.ongoingClass(in: [file], at: at(22, 11, 0), calendar: calendar)
        #expect(ongoing?.end == at(22, 11, 45))
        #expect(ongoing?.fraction(at: at(22, 11, 0)) == 0.4)
        #expect(TodaySummary.ongoingClass(in: [file], at: at(22, 11, 45), calendar: calendar) == nil)
        file.sessions[0].isCancelled = true
        #expect(TodaySummary.ongoingClass(in: [file], at: at(22, 11, 0), calendar: calendar) == nil)
    }

    @Test func courseWithReviewsOffHasNoReviewsOrMissingNotes() {
        let now = at(23, 12)
        var file = CourseFile(course: Course(device: device, at: now, title: "행복의 조건"))
        let session = Session(device: device, at: now, week: 7, index: 1, date: at(20, 10))
        var unit = Unit(device: device, at: now, title: "행복", order: 0)
        unit.sessionIds = [session.id]
        file.sessions = [session]
        file.units = [unit]
        let inputs = { UnitReviewInput.all(for: file, reviews: [], settings: Settings(), calendar: calendar, now: now) }
        #expect(inputs().count == 1)
        #expect(TodaySummary.build(courses: [file], now: now, settings: Settings(), calendar: calendar).missingReviewNotes.count == 1)

        file.course.reviews = false
        #expect(inputs().isEmpty)
        #expect(TodaySummary.build(courses: [file], now: now, settings: Settings(), calendar: calendar).missingReviewNotes.isEmpty)
    }
}
