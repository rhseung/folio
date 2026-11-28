import FolioCore
import FolioDomain
import Foundation
import Testing

// 그래프 이론의 기말이다. 범위는 매칭(자식: 홀의 정리, 증가 경로)과 채색이고, 정리 노트는 홀의 정리와 증가 경로에만 있다.
struct PlanCourse {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    let device = UUID()
    let made = PlanCourse.at(11, 20, 10)
    let course: Course
    var matching: FolioDomain.Unit
    var hall: FolioDomain.Unit
    var paths: FolioDomain.Unit
    var coloring: FolioDomain.Unit
    var notes: [NoteEntry] = []
    var exam: Exam
    var sets: [ProblemSet] = []

    static func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func day(_ month: Int, _ day: Int) -> LocalDate {
        guard let date = LocalDate(year: 2026, month: month, day: day) else { preconditionFailure("\(month)/\(day)") }
        return date
    }

    init() {
        course = Course(device: device, at: made, title: "그래프 이론")
        matching = FolioDomain.Unit(device: device, at: made, title: "매칭", order: 0)
        hall = FolioDomain.Unit(device: device, at: made, title: "홀의 정리", order: 0, parentId: matching.id)
        paths = FolioDomain.Unit(device: device, at: made, title: "증가 경로", order: 1, parentId: matching.id)
        coloring = FolioDomain.Unit(device: device, at: made, title: "채색", order: 1)
        exam = Exam(device: device, at: made, title: "기말고사", start: Self.at(12, 14, 9), end: Self.at(12, 14, 11))
        exam.addedScopeUnitIds = [matching.id, hall.id, paths.id, coloring.id]
        note("기말 10 증가 경로", [paths.id])
        note("기말 02 홀의 정리", [hall.id])
    }

    @discardableResult
    mutating func note(_ title: String, _ units: [UUID], kind: NoteKind = .unit) -> UUID {
        let entry = NoteEntry(id: UUID(), device: device, at: made, path: "Notes/\(title).md", meta: NoteMeta(kind: kind, unitIds: units))
        notes.append(entry)
        return entry.id
    }

    func noteId(_ title: String) -> UUID {
        guard let note = notes.first(where: { $0.title == title }) else { preconditionFailure(title) }
        return note.id
    }

    var file: CourseFile {
        CourseFile(course: course, units: [matching, hall, paths, coloring], exams: [exam], problemSets: sets, notes: notes)
    }

    func study(now: Date, log: StudyLog = StudyLog(), settings: Settings = Settings()) -> CourseStudy {
        CourseStudy(file: file, cards: [], log: log, settings: settings, calendar: Self.calendar, now: now)
    }

    func checks(_ ids: [UUID], at date: Date) -> StudyLog {
        StudyLog(checks: ids.map { (date, PlanCheckEvent(itemId: $0, done: true)) })
    }
}

struct ExamPlanTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func planRoundTrips() throws {
        let note = UUID()
        var original = Exam(device: device, at: at, title: "기말고사")
        original.plan = [
            ExamPlanItem(day: PlanCourse.day(12, 1), target: .note(note, .proof)),
            ExamPlanItem(day: PlanCourse.day(12, 2), target: .custom, title: "교재 3장", edited: true, postponedFrom: PlanCourse.day(12, 1)),
        ]
        original.planPeriod = ExamPlanPeriod(start: PlanCourse.day(11, 28), end: PlanCourse.day(12, 4), after: .mock)
        let data = try JSONEncoder().encode(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((json["plan"] as? [[String: Any]])?.first)
        let target = try #require(first["target"] as? [String: Any])

        #expect(first["day"] as? String == "2026-12-01")
        #expect(target["kind"] as? String == "note" && target["stage"] as? String == "proof")
        #expect(target["id"] as? String == note.uuidString)
        #expect((json["planPeriod"] as? [String: Any])?["after"] as? String == "mock")
        #expect(try JSONDecoder().decode(Exam.self, from: data) == original)
    }

    @Test func examWithoutPlanKeyStillLoads() throws {
        let exam = Exam(device: device, at: at, title: "Midterm")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(exam)) as? [String: Any])
        json["plan"] = nil
        let decoded = try JSONDecoder().decode(Exam.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.plan.isEmpty && decoded.planPeriod == nil)
        #expect(decoded.title == "Midterm")
    }

    @Test func latestCheckWins() {
        let a = UUID(), b = UUID(), c = UUID()
        let t = { (s: Double) in Date(timeIntervalSince1970: s) }

        let events: [(at: Date, event: PlanCheckEvent)] = [
            (t(30), PlanCheckEvent(itemId: a, done: false)),
            (t(10), PlanCheckEvent(itemId: a, done: true)),
            (t(10), PlanCheckEvent(itemId: b, done: true)),
            (t(20), PlanCheckEvent(itemId: b, done: false)),
            (t(40), PlanCheckEvent(itemId: b, done: true, auto: true)),
            (t(5), PlanCheckEvent(itemId: c, done: false)),
        ]
        #expect(ExamPlan.done(events) == [b])
    }

    // MARK: The exam's notes

    @Test func examNotesAreTheScopeUnitsTopicNotesInNaturalNameOrder() {
        var course = PlanCourse()
        course.note("기말 1 매칭의 기초", [course.matching.id])
        course.note("수업 복습", [course.hall.id], kind: .free)
        let outside = FolioDomain.Unit(device: course.device, at: course.made, title: "평면 그래프", order: 2)
        course.note("기말 11 평면 그래프", [outside.id])
        // 숫자를 수로 읽어 1, 02, 10의 차례다. 범위 밖 단원의 노트와 낱개 노트가 아닌 노트는 뺀다.
        #expect(course.file.examNotes(of: course.exam).map(\.title) == ["기말 1 매칭의 기초", "기말 02 홀의 정리", "기말 10 증가 경로"])
    }

    @Test func aScopeUnitWithNoNoteNeedsOneAndParentsAreLeftToTheirChildren() {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        var notes = course.file.planNotes(of: course.exam, proofs: [hall])
        // 매칭은 자식이 범위에 있어 자식으로 본다. 노트가 없는 것은 채색뿐이다.
        #expect(notes.missing == [course.coloring.id])
        #expect(notes.notes.map(\.proof) == [true, false])

        // 부모 단원에 이은 노트는 그 자식을 함께 다룬다.
        course.notes.removeAll()
        course.note("기말 01 매칭", [course.matching.id])
        notes = course.file.planNotes(of: course.exam, proofs: [])
        #expect(notes.missing == [course.coloring.id])

        course.notes.removeAll()
        #expect(course.file.planNotes(of: course.exam, proofs: []).missing == [course.hall.id, course.paths.id, course.coloring.id])
    }

    // MARK: Placing

    @Test func theFirstPlanRunsFromTodayToTheDayBeforeTheExam() throws {
        let course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리"), paths = course.noteId("기말 10 증가 경로")
        let study = course.study(now: PlanCourse.at(12, 8, 15))
        let placed = try #require(study.place(course.exam, proofs: [hall], settings: Settings(), calendar: PlanCourse.calendar))
        #expect(placed.period == ExamPlanPeriod(start: PlanCourse.day(12, 8), end: PlanCourse.day(12, 13)))
        // 엿새에 노트 둘이라 12/8과 12/11이다. 채색의 노트 만들기는 첫날 맨 앞이다.
        #expect(
            placed.plan.map(\.target) == [
                .makeNote(course.coloring.id), .note(hall, .read), .note(hall, .proof), .note(hall, .solve), .note(paths, .read),
                .note(paths, .solve),
            ])
        #expect(placed.plan.map(\.day.day) == [8, 8, 8, 8, 11, 11])
        #expect(placed.basis.examDay == PlanCourse.day(12, 14) && placed.basis.period == placed.period)
    }

    @Test func aStoredPeriodPastAMovedExamIsPulledBack() throws {
        var course = PlanCourse()
        course.exam.planPeriod = ExamPlanPeriod(start: PlanCourse.day(12, 9), end: PlanCourse.day(12, 13), after: .mock)
        course.exam.start = PlanCourse.at(12, 10, 9)
        course.exam.end = nil
        let study = course.study(now: PlanCourse.at(12, 1))
        let placed = try #require(study.place(course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        #expect(placed.period == ExamPlanPeriod(start: PlanCourse.day(12, 9), end: PlanCourse.day(12, 9), after: .mock))
        var undated = course.exam
        undated.start = nil
        #expect(study.place(undated, proofs: [], settings: Settings(), calendar: PlanCourse.calendar) == nil)
    }

    @Test func aPeriodEndingOnTheExamEveFollowsTheExamWhenItIsPutOff() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        #expect(course.exam.planPeriod == ExamPlanPeriod(start: PlanCourse.day(12, 8), end: PlanCourse.day(12, 13)))
        func placed(_ course: PlanCourse) throws -> ExamPlan.Placement {
            try #require(
                course.study(now: PlanCourse.at(12, 8, 13)).place(
                    course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        }
        // 시험을 12/14에서 12/18로 늦추면 끝낼 날이 12/17로 따라간다. 열흘에 노트 둘이라 12/8과 12/13이다.
        var later = course
        later.exam.start = PlanCourse.at(12, 18, 9)
        later.exam.end = nil
        #expect(try placed(later).period == ExamPlanPeriod(start: PlanCourse.day(12, 8), end: PlanCourse.day(12, 17)))
        #expect(try placed(later).plan.filter { $0.target.kind == .note }.map(\.day.day) == [8, 8, 13, 13])

        // 시험 전날보다 일찍 끝내기로 한 기간은 시험을 늦춰도 그대로다.
        var early = later
        early.exam.planPeriod?.end = PlanCourse.day(12, 11)
        #expect(try placed(early).period == ExamPlanPeriod(start: PlanCourse.day(12, 8), end: PlanCourse.day(12, 11)))
    }

    @Test func fittingAPeriodFollowsOnlyAnEndOnTheOldExamEve() {
        let day = PlanCourse.day
        let period = ExamPlanPeriod(start: day(12, 5), end: day(12, 9), after: .mock)
        // 예전 시험이 12/10이면 끝낼 날이 그 전날이었으므로 늦춰도 앞당겨도 새 시험 전날이다.
        #expect(period.fitted(before: day(12, 15), from: day(12, 10)).end == day(12, 14))
        #expect(period.fitted(before: day(12, 8), from: day(12, 10)) == ExamPlanPeriod(start: day(12, 5), end: day(12, 7), after: .mock))
        // 예전 시험이 12/12면 일찍 끝내기로 한 기간이라 그대로고, 시험 날을 넘을 때만 당긴다.
        #expect(period.fitted(before: day(12, 15), from: day(12, 12)) == period)
        #expect(period.fitted(before: day(12, 8), from: day(12, 12)).end == day(12, 7))
        // 예전 시험 날을 모르면 당기기만 한다.
        #expect(period.fitted(before: day(12, 15)) == period)
        // 시작일이 새 끝낼 날보다 뒤면 함께 당긴다.
        #expect(period.fitted(before: day(12, 4), from: day(12, 10)) == ExamPlanPeriod(start: day(12, 3), end: day(12, 3), after: .mock))
    }

    @Test func itemsCanSitFromTodayToTheDayBeforeTheExam() {
        let day = PlanCourse.day
        #expect(Exam.planDays(today: day(12, 11), examDay: day(12, 14)) == [day(12, 11), day(12, 12), day(12, 13)])
        // 시험 날과 그 뒤에는 옮길 날이 없다.
        #expect(Exam.planDays(today: day(12, 14), examDay: day(12, 14)).isEmpty)
        #expect(Exam.planDays(today: day(12, 20), examDay: day(12, 14)).isEmpty)

        // 새벽 3:59는 아직 12/11의 공부일이고 4:00부터 12/12다.
        let course = PlanCourse()
        func days(_ exam: Exam, at now: Date) -> [LocalDate] {
            course.study(now: now).planDays(of: exam, settings: Settings(), calendar: PlanCourse.calendar)
        }
        #expect(days(course.exam, at: PlanCourse.at(12, 12, 3, 59)).first == day(12, 11))
        #expect(days(course.exam, at: PlanCourse.at(12, 12, 4, 0)) == [day(12, 12), day(12, 13)])
        var undated = course.exam
        undated.start = nil
        #expect(days(undated, at: PlanCourse.at(12, 12)).isEmpty)
    }

    @Test func theDefaultPeriodStartsOnTheStudyDayNotTheCalendarDay() throws {
        let course = PlanCourse()
        // 새벽 3:59는 아직 12/7의 공부일이고 4:00부터 12/8이다.
        let before = try #require(
            course.study(now: PlanCourse.at(12, 8, 3, 59)).place(
                course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        let after = try #require(
            course.study(now: PlanCourse.at(12, 8, 4, 0)).place(
                course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        #expect(before.period.start == PlanCourse.day(12, 7) && after.period.start == PlanCourse.day(12, 8))
        #expect(before.period.end == PlanCourse.day(12, 13) && after.period.end == PlanCourse.day(12, 13))
    }

    // MARK: When to place again

    @Test func aPlanIsPlacedAgainOnlyWhenItsBasisChanges() throws {
        var course = PlanCourse()
        let settings = Settings(), calendar = PlanCourse.calendar
        let hall = course.noteId("기말 02 홀의 정리")
        let today = PlanCourse.day(12, 1)
        func needs(_ course: PlanCourse, proofs: Set<UUID> = [hall], today: LocalDate = today) -> Bool {
            course.file.needsPlan(course.exam, proofs: proofs, today: today, settings: settings, calendar: calendar)
        }
        // 계획이 아직 없으면 놓는다.
        #expect(needs(course))
        let placed = try #require(
            course.study(now: PlanCourse.at(12, 1)).place(course.exam, proofs: [hall], settings: settings, calendar: calendar))
        course.exam.plan = placed.plan
        course.exam.planPeriod = placed.period
        course.exam.planBasis = placed.basis
        #expect(!needs(course))
        // 공부일이 바뀌어도 다시 놓지 않는다.
        #expect(!needs(course, today: today.adding(days: 1)) && !needs(course, today: today.adding(days: 5)))

        var added = course
        added.note("기말 11 채색", [course.coloring.id])
        #expect(needs(added))
        var renamed = course
        renamed.notes[0].path = "Notes/기말 01 증가 경로.md"
        #expect(needs(renamed))
        #expect(needs(course, proofs: []))
        var longer = course
        longer.exam.planPeriod?.end = PlanCourse.day(12, 10)
        #expect(needs(longer))
        var mock = course
        mock.exam.planPeriod?.after = .mock
        #expect(needs(mock))
        var moved = course
        moved.exam.start = PlanCourse.at(12, 16, 9)
        #expect(needs(moved))

        // 시험 날과 그 뒤에는 놓지 않고, 범위나 날짜가 없는 시험도 놓지 않는다.
        var fresh = PlanCourse()
        #expect(!needs(fresh, today: PlanCourse.day(12, 14)) && needs(fresh, today: PlanCourse.day(12, 13)))
        fresh.exam.addedScopeUnitIds = []
        #expect(!needs(fresh))
        fresh = PlanCourse()
        fresh.exam.start = nil
        #expect(!needs(fresh))
    }

    // MARK: Rows

    func planned(_ course: inout PlanCourse, on now: Date, proofs: Set<UUID>) throws {
        let placed = try #require(
            course.study(now: now).place(course.exam, proofs: proofs, settings: Settings(), calendar: PlanCourse.calendar))
        course.exam.plan = placed.plan
        course.exam.planPeriod = placed.period
        course.exam.planBasis = placed.basis
    }

    @Test func aNoteIsOneRowWithItsStagesInOrder() throws {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리"), paths = course.noteId("기말 10 증가 경로")
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [hall])
        let read = try #require(course.exam.plan.first { $0.target == .note(hall, .read) })
        let study = course.study(now: PlanCourse.at(12, 8, 20), log: course.checks([read.id], at: PlanCourse.at(12, 8, 19)))
        let board = study.planBoard([course.exam])

        #expect(board.today.map(\.title) == ["정리 노트 만들기", "기말 02 홀의 정리"])
        #expect(board.today[0].kind == .makeNote(unit: course.coloring.id) && board.today[0].subject == "채색")
        #expect(board.today[1].steps.map(\.stage) == [.read, .proof, .solve])
        #expect(board.today[1].steps.map(\.isDone) == [true, false, false])
        #expect(board.today[1].steps.map(\.progress.done) == [1, 0, 0] && board.today[1].doneSteps == 1)
        #expect(board.today.allSatisfy { !$0.isLate })
        #expect(board.next.map(\.day) == [PlanCourse.day(12, 11)])
        #expect(board.next[0].rows.map(\.kind) == [.note(paths)] && board.next[0].rows[0].steps.count == 2)
        #expect((board.notes, board.wrong, board.late, board.left, board.nextNotes, board.nextMocks) == (1, 0, 0, 2, 1, 0))
    }

    @Test func unfinishedItemsOfPastDaysSitOnTodayAsLateWithoutChangingTheFile() throws {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [hall])
        let read = try #require(course.exam.plan.first { $0.target == .note(hall, .read) })
        let stored = course.exam.plan
        let log = course.checks([read.id], at: PlanCourse.at(12, 8, 19))

        // 다음 날 새벽 3:59는 아직 12/8이라 밀리지 않았다. 4:00부터 밀린다.
        let before = course.study(now: PlanCourse.at(12, 9, 3, 59), log: log).planBoard([course.exam])
        #expect(before.late == 0 && before.today.count == 2)
        let after = course.study(now: PlanCourse.at(12, 9, 4, 0), log: log).planBoard([course.exam])
        #expect(after.today.map(\.lateFrom) == [PlanCourse.day(12, 8), PlanCourse.day(12, 8)])
        // 끝낸 정독은 그날에 남고, 남은 증명과 문제풀이만 오늘에 얹힌다.
        #expect(after.today[1].steps.map(\.stage) == [.proof, .solve] && after.today[1].day == PlanCourse.day(12, 9))
        #expect(after.late == 2 && course.exam.plan == stored)

        // 이틀 뒤에는 그날의 노트와 한 블록에 있다. 밀린 줄도 노트 이름 순서를 따른다.
        let later = course.study(now: PlanCourse.at(12, 11, 9), log: log).planBoard([course.exam])
        #expect(later.today.map(\.title) == ["정리 노트 만들기", "기말 02 홀의 정리", "기말 10 증가 경로"])
        #expect(later.today.map(\.isLate) == [true, true, false] && later.next.isEmpty)
    }

    @Test func yesterdaysWrongAnswersLeadTodayAndAreNotStored() throws {
        var course = PlanCourse()
        let set = ProblemSet(
            device: course.device, at: course.made, title: "연습", source: .exercise,
            problems: [Problem(number: "1", unitIds: [course.hall.id]), Problem(number: "2", unitIds: [course.coloring.id])])
        course.sets = [set]
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        let wrong = { (i: Int) in ProblemSolveEvent(setId: set.id, problemId: set.problems[i].id, verdict: .wrong, basis: .solution) }
        let right = ProblemSolveEvent(setId: set.id, problemId: set.problems[0].id, verdict: .correct, basis: .solution)

        let clean = course.study(now: PlanCourse.at(12, 8, 20))
        #expect(clean.wrongRow == nil && clean.planBoard([course.exam]).wrong == 0)

        let solves = [(PlanCourse.at(12, 8, 10), wrong(0)), (PlanCourse.at(12, 8, 11), wrong(1))]
        let study = course.study(now: PlanCourse.at(12, 9, 10), log: StudyLog(solves: solves))
        let board = study.planBoard([course.exam])
        #expect(board.today.first?.kind == .wrong(PlanProgress(done: 0, total: 2)) && board.today.first?.title == "어제 오답")
        #expect(board.today.first?.isDone == false && study.wrongProgress.left == 2)
        #expect(board.wrong == 2 && board.today.first?.commands(today: study.today) == [])
        #expect(!course.exam.plan.contains { $0.title == "어제 오답" })
        #expect(study.solve(board.today[0], seed: 1)?.problems == set.problems.map(\.id))

        // 다음 공부일에 맞힌 문제는 오답에서 빠진다.
        let fixed = course.study(now: PlanCourse.at(12, 9, 12), log: StudyLog(solves: solves + [(PlanCourse.at(12, 9, 11), right)]))
        #expect(fixed.planBoard([course.exam]).today.first?.kind == .wrong(PlanProgress(done: 0, total: 1)))
    }

    @Test func twoExamsOfACourseShareOneBoardWithNoteMakingFirst() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        var quiz = Exam(device: course.device, at: course.made, title: "Quiz 5", start: PlanCourse.at(12, 10, 9))
        quiz.plan = [
            ExamPlanItem(day: PlanCourse.day(12, 8), target: .custom, title: "족보 훑기", edited: true),
            ExamPlanItem(day: PlanCourse.day(12, 8), target: .makeNote(course.hall.id)),
        ]
        let board = course.study(now: PlanCourse.at(12, 8, 12)).planBoard([quiz, course.exam])
        // 가까운 퀴즈의 줄이 앞이지만, 노트 만들기는 어느 시험 것이든 노트 공부보다 앞이고 직접 쓴 할 일은 맨 뒤다.
        #expect(board.today.map(\.kind.isMakeNote) == [true, true, false, false])
        #expect(board.today.map(\.examId) == [quiz.id, course.exam.id, course.exam.id, quiz.id])
    }

    @Test func boardsOfSeveralCoursesMergeByKindOfRow() {
        let day = PlanCourse.day(12, 1)
        func row(_ kind: PlanRow.Kind, _ title: String, late: Bool = false) -> PlanRow {
            PlanRow(
                id: title, courseId: UUID(), examId: UUID(), kind: kind, title: title, subject: nil, day: day,
                lateFrom: late ? day.adding(days: -1) : nil, steps: [])
        }
        let graph = PlanBoard(
            today: [
                row(.wrong(PlanProgress(done: 1, total: 4)), "어제 오답"), row(.note(UUID()), "기말 03", late: true),
                row(.note(UUID()), "기말 04"),
            ],
            next: [PlanBoard.Day(day: day.adding(days: 1), rows: [row(.note(UUID()), "기말 05")])])
        let stats = PlanBoard(
            today: [row(.makeNote(unit: UUID()), "정리 노트 만들기"), row(.note(UUID()), "기말 02"), row(.custom, "교재")],
            next: [
                PlanBoard.Day(day: day.adding(days: 1), rows: [row(.note(UUID()), "기말 03 큰 수")]),
                PlanBoard.Day(day: day.adding(days: 2), rows: [row(.mock, "모의고사")]),
            ])
        let merged = PlanBoard.merged([graph, stats])
        #expect(merged.today.map(\.title) == ["어제 오답", "정리 노트 만들기", "기말 03", "기말 04", "기말 02", "교재"])
        #expect(merged.next.map(\.rows.count) == [2, 1])
        // 오답 넷 가운데 하나를 다시 맞혔으면 남은 오답은 셋이다.
        #expect((merged.notes, merged.wrong, merged.late, merged.nextNotes, merged.nextMocks) == (3, 3, 1, 2, 1))
    }

    @Test func aRowsMenuFollowsItsDayAndWhatIsLeft() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        let study = course.study(now: PlanCourse.at(12, 8, 12))
        let board = study.planBoard([course.exam])
        let today = try #require(board.today.last), later = try #require(board.next.first?.rows.first)
        #expect(today.commands(today: study.today) == [.postpone, .pickDay, .done(false), .remove])
        #expect(later.commands(today: study.today) == [.advance, .postpone, .pickDay, .done(false), .remove])

        let done = course.study(now: PlanCourse.at(12, 8, 12), log: course.checks(today.open, at: PlanCourse.at(12, 8, 11)))
        let finished = try #require(done.planBoard([course.exam]).today.last)
        #expect(finished.isDone && finished.open.isEmpty && finished.commands(today: done.today) == [.done(true), .remove])
    }

    @Test func aStepOpensItsNoteOrTheProblemsPage() throws {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [hall])
        let board = course.study(now: PlanCourse.at(12, 8, 12)).planBoard([course.exam])
        let courseId = course.course.id
        #expect(board.today[0].link(for: nil) == AppLink(.unit, course.coloring.id))
        #expect(board.today[1].link(for: .read) == AppLink(.note, hall))
        #expect(board.today[1].link(for: .proof) == .course(courseId, page: .problems))
        #expect(board.today[1].link(for: .solve) == .course(courseId, page: .problems))
    }

    // MARK: Progress

    @Test func aStepIsDoneWhenItsProgressReachesTheTotal() {
        #expect(PlanProgress(done: 3, total: 3).isDone && PlanProgress(done: 4, total: 3).isDone)
        #expect(!PlanProgress(done: 2, total: 3).isDone && PlanProgress(done: 2, total: 3).isStarted)
        #expect(!PlanProgress(done: 0, total: 3).isDone && !PlanProgress(done: 0, total: 3).isStarted)
        // 전체가 없으면 끝낼 것이 정해지지 않았다.
        #expect(!PlanProgress(done: 0, total: 0).isDone)
        #expect(PlanProgress(done: 6, total: 14).left == 8 && PlanProgress(done: 7, total: 14).fraction == 0.5)
        #expect(PlanProgress(done: 20, total: 14).left == 0 && PlanProgress(done: 20, total: 14).fraction == 1)

        let half = PlanRow.Step(item: UUID(), stage: .read, progress: PlanProgress(done: 6, total: 14))
        let full = PlanRow.Step(item: UUID(), stage: .proof, progress: PlanProgress(done: 5, total: 5))
        var row = PlanRow(
            id: "row", courseId: UUID(), examId: UUID(), kind: .note(UUID()), title: "기말 04", subject: nil, day: PlanCourse.day(12, 1),
            lateFrom: nil, steps: [half, full])
        // 하다 만 단계는 남은 단계라 미루면 함께 간다.
        #expect(!half.isDone && full.isDone && !row.isDone && row.open == [half.item] && row.doneSteps == 1)
        row.steps[0].progress.done = 14
        #expect(row.isDone && row.open.isEmpty)
        #expect(
            PlanRow(
                id: "wrong", courseId: UUID(), examId: nil, kind: .wrong(PlanProgress(done: 2, total: 2)), title: "어제 오답", subject: nil,
                day: PlanCourse.day(12, 1), lateFrom: nil, steps: []
            ).isDone)
    }

    @Test func aCheckedItemIsWhollyDoneAndAnUncheckedOneHasNoProgress() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        let items = course.exam.plan
        let study = course.study(now: PlanCourse.at(12, 8, 20), log: course.checks([items[0].id], at: PlanCourse.at(12, 8, 19)))
        #expect(study.progress(of: items[0]) == PlanProgress(done: 1, total: 1) && study.isDone(items[0]))
        #expect(study.progress(of: items[1]) == PlanProgress(done: 0, total: 1) && !study.isDone(items[1]))
    }

    @Test func postponingKeepsTheProgressOfWhatItMoves() throws {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [hall])
        let read = try #require(course.exam.plan.first { $0.target == .note(hall, .read) })
        let proof = try #require(course.exam.plan.first { $0.target == .note(hall, .proof) })
        let log = course.checks([read.id], at: PlanCourse.at(12, 8, 19))
        let before = course.study(now: PlanCourse.at(12, 8, 20), log: log)
        let progress = [read, proof].map(before.progress(of:))

        // 끝낸 정독과 하지 않은 증명을 함께 내일로 옮긴다. 진행은 항목에 붙어 있어 날이 바뀌어도 같다.
        course.exam.postponePlan([read.id, proof.id], today: before.today)
        let after = course.study(now: PlanCourse.at(12, 8, 21), log: log)
        let moved = try #require(after.planBoard([course.exam]).next.first { $0.day == PlanCourse.day(12, 9) }?.rows.first)
        #expect(moved.steps.map(\.stage) == [.read, .proof] && moved.steps.map(\.progress) == progress)
        #expect(moved.steps.map(\.isDone) == [true, false] && moved.lateFrom == PlanCourse.day(12, 8))
    }

    // MARK: Moving

    @Test func postponedItemsStayLateWhereTheyLandAndAdvancingBackClearsIt() {
        var exam = Exam(device: device, at: at, title: "기말고사")
        let today = PlanCourse.day(12, 1)
        let missed = ExamPlanItem(day: today.adding(days: -2), target: .note(UUID(), .solve))
        let todays = ExamPlanItem(day: today, target: .note(UUID(), .read))
        let later = ExamPlanItem(day: today.adding(days: 3), target: .mock)
        exam.plan = [missed, todays, later]

        // 못 하고 지난 항목은 오늘에 얹혀 있으므로 내일로 간다. 뒤 날의 항목은 그 다음 날로 간다.
        exam.postponePlan([missed.id, later.id], today: today)
        #expect(exam.plan.map(\.day) == [today.adding(days: 1), today, today.adding(days: 4)])
        #expect(exam.plan.map(\.postponedFrom) == [missed.day, nil, later.day])
        #expect(exam.plan[2].lateFrom(today: today, done: false) == later.day && exam.plan[2].lateFrom(today: today, done: true) == nil)
        // 한 번 더 미뤄도 처음 있던 날을 기억한다.
        exam.postponePlan([later.id], today: today)
        #expect(exam.plan[2].day == today.adding(days: 5) && exam.plan[2].postponedFrom == later.day)

        // 오늘로 앞당기면 원래 날보다 앞이라 밀린 것이 아니다. 오늘이나 지난 날의 항목은 앞당길 것이 없다.
        exam.advancePlan([later.id, todays.id], today: today)
        #expect(exam.plan[2].day == today && exam.plan[2].postponedFrom == nil && exam.plan[2].isEdited)
        #expect(exam.plan[1] == todays)
        // 원래 날이 지난 항목은 앞당겨도 밀린 채다.
        exam.plan[0].day = today.adding(days: 2)
        exam.advancePlan([missed.id], today: today)
        #expect(exam.plan[0].day == today && exam.plan[0].postponedFrom == missed.day)

        exam.movePlan([missed.id], to: today.adding(days: 6))
        #expect(exam.plan[0].day == today.adding(days: 6) && exam.plan[0].postponedFrom == nil)
    }

    // MARK: Names and progress

    @Test func placedItemsAreNamedFromTheirTarget() {
        let course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let day = PlanCourse.day(12, 1)
        let file = course.file
        #expect(file.title(of: ExamPlanItem(day: day, target: .note(hall, .proof))) == "기말 02 홀의 정리 증명")
        #expect(file.title(of: ExamPlanItem(day: day, target: .makeNote(course.coloring.id))) == "채색 정리 노트 만들기")
        #expect(file.title(of: ExamPlanItem(day: day, target: .mock)) == "모의고사")
        #expect(file.title(of: ExamPlanItem(day: day, target: .custom, title: "교재 3장")) == "교재 3장")
        #expect(file.name(of: course.exam.id) == "기말고사")
    }

    @Test func anExamIsOnTrackWhileNothingIsLate() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        #expect(course.study(now: PlanCourse.at(12, 8, 20)).study(of: course.exam).onTrack)
        let slipped = course.study(now: PlanCourse.at(12, 9, 9)).study(of: course.exam)
        #expect(!slipped.onTrack && slipped.planLate == 3)
        let done = course.exam.plan.filter { $0.day == PlanCourse.day(12, 8) }.map(\.id)
        #expect(
            course.study(now: PlanCourse.at(12, 9, 9), log: course.checks(done, at: PlanCourse.at(12, 9, 8))).study(of: course.exam).onTrack
        )
    }

    @Test func plansOfExamsThatAreOverLeaveTheBoard() throws {
        var course = PlanCourse()
        try planned(&course, on: PlanCourse.at(12, 8), proofs: [])
        let study = course.study(now: PlanCourse.at(12, 13, 9))
        #expect(study.plannedExams(now: PlanCourse.at(12, 13, 9), calendar: PlanCourse.calendar).map(\.id) == [course.exam.id])
        let over = course.study(now: PlanCourse.at(12, 14, 12))
        #expect(over.plannedExams(now: PlanCourse.at(12, 14, 12), calendar: PlanCourse.calendar).isEmpty)
    }
}
