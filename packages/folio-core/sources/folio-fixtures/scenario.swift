import FolioActions
import FolioDomain
import FolioStorage
import Foundation

/// Situations to judge a screen against: `Fixture.standard` grown through the actions around a pinned moment, so a
/// render or preview shows the same day whatever the real clock says. Nothing here comes from real data.
public enum Scenario: String, CaseIterable, Sendable {
    /// Six classes with the second under way, overdue reviews, deadlines into next month, three exams.
    case busyDay
    /// The same day with six exams in the next month, more than fit side by side.
    case manyExams
    /// A Saturday: no classes and a few things pending.
    case quietDay
    /// The term's first day, nothing scheduled yet.
    case empty

    /// Korean time: the class times and dues below are a Korean student's day.
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        return c
    }()

    public var now: Date {
        switch self {
        case .busyDay, .manyExams: Self.at(2026, 11, 4, 11, 20)
        case .quietDay: Self.at(2026, 11, 7, 15, 0)
        case .empty: Self.at(2026, 9, 1, 9, 0)
        }
    }

    public func write(to folder: URL) throws {
        try Fixture.standard.write(to: folder)
        let build = Builder(gist: GISTStore(url: folder))
        switch self {
        case .busyDay: try build.busyDay()
        case .manyExams: try build.busyDay(extraExams: true)
        case .quietDay: try build.quietDay()
        case .empty: break
        }
    }

    public func copyToTemp() throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appending(path: "folio-\(rawValue)-\(UUID().uuidString)/GIST")
        try write(to: dest)
        return dest
    }

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}

private struct Builder {
    let gist: GISTStore
    let device = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
    let fall = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000003")!
    let graph = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let robotics = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!
    let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!

    func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { Scenario.at(2026, m, d, h, min) }

    /// Each action runs at its own moment, so notes, reviews and edits are stamped when they would have happened.
    @discardableResult
    func run(_ action: some Action, at now: Date) throws -> UUID {
        let ctx = ActionContext(gist: gist, device: device, now: now, calendar: Scenario.calendar)
        try action.run(ctx)
        return ctx.made ?? UUID()
    }

    func slots(_ weekdays: [Int], _ start: Int, _ end: Int, _ room: String) -> [ClassTime] {
        weekdays.map { ClassTime(weekday: $0, startMinute: start, endMinute: end, room: room) }
    }

    /// A held class whose review note is written, or left half done.
    @discardableResult
    func session(_ course: UUID, _ date: Date, minutes: Int = 75, note: Bool = true, unfinished: Bool = false) throws -> UUID {
        let id = try run(SessionAdd(course: course, date: date), at: date)
        if note {
            let end = date.addingTimeInterval(TimeInterval(minutes * 60))
            try run(SessionNote(course: course, session: id, kind: .review), at: end)
            if !unfinished { try run(SessionSet(course: course, session: id, cancelled: .keep, skipsReview: .keep, reviewUnfinished: .set(false)), at: end) }
        }
        return id
    }

    func unit(_ course: UUID, _ title: String, _ sessions: [UUID], at date: Date) throws -> UUID {
        let id = try run(UnitAdd(course: course, title: title), at: date)
        try run(UnitLink(course: course, unit: id, sessions: sessions), at: date)
        return id
    }

    func review(_ course: UUID, _ unit: UUID, _ result: ReviewResult, _ start: Date, minutes: Int) throws {
        try run(ReviewRecord(course: course, unit: unit, result: result, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60))), at: start)
    }

    func busyDay(extraExams: Bool = false) throws {
        let setup = at(8, 28, 10)
        let codes = ["EC", "MA", "PS", "GS"].map { CourseCode(device: device, at: setup, prefix: $0) }
        // Invented scale, categories and people: the repo is public, so nothing here is a real grade or person.
        let grades = [("A+", 4.5), ("A0", 4.0), ("B+", 3.5), ("B0", 3.0), ("C+", 2.5), ("C0", 2.0), ("D+", 1.5), ("D0", 1.0), ("F", 0.0)]
            .map { LetterGrade(device: device, at: setup, symbol: $0.0, points: $0.1, countsInGpa: true, countsInCredits: $0.0 != "F") }
            + [LetterGrade(device: device, at: setup, symbol: "S", points: nil, countsInGpa: false, countsInCredits: true)]
        let major = Category(device: device, at: setup, name: "전공", group: "전공", isMajor: true, minCredits: 36)
        let science = Category(device: device, at: setup, name: "기초과학", group: "기초", minCredits: 30)
        let humanities = Category(device: device, at: setup, name: "인문사회", group: "교양", minCredits: 24)
        // Fixed ids: avatar colors follow them.
        let people = [
            Person(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!, device: device, at: setup, name: "김도윤", email: "doyun@example.com", office: "A동 412", officeHours: "화 14:00-16:00"),
            Person(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!, device: device, at: setup, name: "이서연", email: "seoyeon@example.com", office: "C동 301", officeHours: "목 10:00-11:00"),
            Person(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!, device: device, at: setup, name: "박준호", email: "junho@example.com", role: .lecturer, office: "B동 208"),
            Person(id: UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!, device: device, at: setup, name: "최하은", email: "haeun@example.com", role: .assistant, office: "A동 405", memo: "그래프 이론 조교"),
        ]
        try run(CatalogSet(catalog: Catalog(codes: codes, categories: [major, science, humanities], letterGrades: grades, people: people)), at: setup)
        let os = try run(CourseAdd(semester: fall, title: "운영체제", code: codes[0].id, number: "3204", credits: 3, mode: .relative), at: setup)
        let prob = try run(CourseAdd(semester: fall, title: "확률과 통계", code: codes[1].id, number: "2004", credits: 3, mode: .relative), at: setup)
        let physics = try run(CourseAdd(semester: fall, title: "일반물리학", code: codes[2].id, number: "1102", credits: 3, mode: .absolute), at: setup)
        let writing = try run(CourseAdd(semester: fall, title: "글쓰기의 기초", code: codes[3].id, number: "1511", credits: 2, mode: .passFail), at: setup)

        // Mon/Wed back to back, the way a full GIST timetable runs, and an evening class on Wednesdays.
        let timetable: [(UUID, [ClassTime], String)] = [
            (graph, slots([1, 3], 540, 615, "A101"), "point.3.connected.trianglepath.dotted"),
            (robotics, slots([1, 3], 630, 705, "C204"), "gearshape.2"),
            (os, slots([1, 3], 780, 855, "B115"), "cpu"),
            (prob, slots([1, 3], 870, 945, "A203"), "dice"),
            (physics, slots([1, 3], 960, 1035, "Physics 101"), "atom"),
            (writing, slots([3], 1140, 1250, "N210"), "pencil.line"),
        ]
        for (course, schedule, icon) in timetable {
            try run(CourseSet(course: course, fields: [.schedule(schedule), .icon(icon)]), at: setup)
        }

        let staffed: [(UUID, [UUID], FolioDomain.Category)] = [
            (graph, [people[0].id, people[3].id], major), (robotics, [people[1].id], major), (os, [people[2].id], major),
            (prob, [people[2].id], science), (physics, [], science), (writing, [], humanities), (linearAlgebra, [people[0].id], science),
        ]
        for (course, instructors, category) in staffed {
            try run(CourseSet(course: course, fields: [.instructors(instructors), .categories([category.id])]), at: setup)
        }
        try run(CourseSet(course: linearAlgebra, fields: [.finalGrade(grades[1].id)]), at: at(6, 30, 12))
        try gradeBook(graph, at: setup)

        // The last two weeks of classes. Notes are written up to last week; this Monday's still owe theirs.
        var held: [UUID: [Date: UUID]] = [:]
        for (course, schedule, _) in timetable {
            for day in [at(10, 19), at(10, 21), at(10, 26), at(10, 28), at(11, 2), at(11, 4)] {
                let weekday = Scenario.calendar.isoWeekday(of: day)
                guard let slot = schedule.first(where: { $0.weekday == weekday }) else { continue }
                let start = day.addingTimeInterval(TimeInterval(slot.startMinute * 60))
                let today = day == at(11, 4)
                let thisWeek = day >= at(11, 2)
                held[course, default: [:]][day] = try session(course, start, minutes: slot.endMinute - slot.startMinute,
                                                              note: !today && (!thisWeek || course == physics), unfinished: course == physics && thisWeek)
            }
        }
        func s(_ course: UUID, _ m: Int, _ d: Int) -> UUID { held[course]![at(m, d)]! }

        let matching = try unit(graph, "매칭", [s(graph, 10, 19), s(graph, 10, 21)], at: at(10, 21, 11))
        let coloring = try unit(graph, "그래프 채색", [s(graph, 10, 26), s(graph, 10, 28)], at: at(10, 28, 11))
        let scheduling = try unit(os, "프로세스 스케줄링", [s(os, 10, 19), s(os, 10, 21)], at: at(10, 21, 15))
        _ = try unit(os, "교착 상태", [s(os, 10, 26)], at: at(10, 26, 15))
        let conditional = try unit(prob, "조건부 확률", [s(prob, 10, 26), s(prob, 10, 28)], at: at(10, 28, 16))
        let kinematics = try unit(robotics, "순기구학", [s(robotics, 10, 21), s(robotics, 10, 26)], at: at(10, 26, 12))
        _ = try unit(robotics, "역기구학과 야코비안", [s(robotics, 10, 28)], at: at(10, 28, 12))
        _ = try unit(physics, "전기장과 가우스 법칙", [s(physics, 10, 26), s(physics, 10, 28)], at: at(10, 28, 18))

        // A streak up to this morning, which also fills the study-time chart.
        try review(graph, matching, .good, at(10, 23, 21), minutes: 40)
        try review(os, scheduling, .hard, at(10, 30, 20), minutes: 55)
        try review(graph, matching, .good, at(11, 1, 14), minutes: 30)
        try review(robotics, kinematics, .again, at(11, 2, 21), minutes: 45)
        try review(prob, conditional, .good, at(11, 3, 22), minutes: 35)
        try review(graph, coloring, .easy, at(11, 4, 8), minutes: 25)

        let deadlines: [(UUID, String, Date, AssignmentStatus)] = [
            (writing, "에세이 초안", at(11, 4, 18), .todo),
            (os, "HW4", at(11, 4, 23, 59), .doing),
            (prob, "HW6", at(11, 5, 23, 59), .todo),
            (graph, "HW5", at(11, 6, 23, 59), .todo),
            (robotics, "Lab5 보고서", at(11, 9, 23, 59), .todo),
            (physics, "HW7", at(11, 12, 23, 59), .todo),
            (os, "Project 2", at(11, 23, 23, 59), .doing),
            (graph, "SP2", at(12, 2, 23, 59), .todo),
            (robotics, "Final Project", at(12, 18, 23, 59), .todo),
        ]
        for (course, title, due, status) in deadlines {
            let id = try run(AssignmentAdd(course: course, title: title, due: due), at: at(10, 20, 9))
            if status != .todo { try run(AssignmentStatusSet(course: course, assignment: id, status: status), at: at(11, 3, 20)) }
        }

        let quiz = try run(ExamAdd(course: prob, title: "Quiz 3", kind: .quiz, start: at(11, 6, 14, 30), end: at(11, 6, 15), location: "A203"), at: setup)
        try run(ExamAdd(course: physics, title: "2차 시험", kind: .other, start: at(11, 13, 19), end: at(11, 13, 21), location: "Physics 101"), at: setup)
        try run(ExamAdd(course: os, title: "기말고사", kind: .final, start: at(12, 2, 13), end: at(12, 2, 15), location: "B115"), at: setup)
        try run(ExamAdd(course: graph, title: "기말고사", kind: .final, start: at(12, 14, 9), end: at(12, 14, 11), location: "A101"), at: setup)
        if extraExams {
            try run(ExamAdd(course: writing, title: "에세이 발표", kind: .other, start: at(11, 11, 19), end: at(11, 11, 21), location: "N210"), at: setup)
            try run(ExamAdd(course: robotics, title: "중간 발표", kind: .midterm, start: at(11, 18, 10, 30), end: at(11, 18, 12), location: "C204"), at: setup)
            try run(ExamAdd(course: graph, title: "Quiz 4", kind: .quiz, start: at(11, 25, 9), end: at(11, 25, 9, 30), location: "A101"), at: setup)
        }
        try run(ExamPlanAdd(course: prob, exam: quiz, title: "조건부 확률 연습문제 풀기", day: LocalDate(at(11, 4), in: Scenario.calendar), unit: conditional), at: at(11, 1, 10))
    }

    /// A syllabus with scores in so far, so the course's grade page has a curve and a projection to draw.
    func gradeBook(_ course: UUID, at setup: Date) throws {
        let homework = try run(ComponentAdd(course: course, name: "과제", weight: 30, expectedCount: 6), at: setup)
        let quizzes = try run(ComponentAdd(course: course, name: "퀴즈", weight: 20, aggregation: .dropLowest(1), expectedCount: 5), at: setup)
        let midterm = try run(ComponentAdd(course: course, name: "중간고사", weight: 25, aggregation: .single), at: setup)
        try run(ComponentAdd(course: course, name: "기말고사", weight: 25, aggregation: .single), at: setup)
        for (i, (score, day)) in [(9.0, at(9, 15)), (10, at(9, 29)), (7.5, at(10, 13)), (9, at(10, 27))].enumerated() {
            try run(ScoreAdd(course: course, component: homework, title: "HW\(i + 1)", score: score, max: 10, date: LocalDate(day, in: Scenario.calendar)), at: day)
        }
        for (i, (score, day)) in [(8.0, at(9, 22)), (5, at(10, 6)), (9, at(10, 20))].enumerated() {
            try run(ScoreAdd(course: course, component: quizzes, title: "Quiz \(i + 1)", score: score, max: 10, date: LocalDate(day, in: Scenario.calendar)), at: day)
        }
        try run(ScoreAdd(course: course, component: midterm, title: "중간고사", score: 72, max: 100, mean: 61.5, stdDev: 12,
                         date: LocalDate(at(10, 21), in: Scenario.calendar)), at: at(10, 23))
    }

    func quietDay() throws {
        let setup = at(8, 28, 10)
        try run(CourseSet(course: graph, fields: [.schedule(slots([1, 3], 540, 615, "A101")), .icon("point.3.connected.trianglepath.dotted")]), at: setup)
        try run(CourseSet(course: robotics, fields: [.schedule(slots([2, 4], 630, 705, "C204")), .icon("gearshape.2")]), at: setup)
        let monday = try session(graph, at(11, 2, 9), note: true)
        let wednesday = try session(graph, at(11, 4, 9), note: true)
        try session(robotics, at(11, 3, 10, 30), note: true)
        try session(robotics, at(11, 5, 10, 30), note: false)
        _ = try unit(graph, "매칭", [monday, wednesday], at: at(11, 4, 11))
        try run(AssignmentAdd(course: graph, title: "HW5", due: at(11, 9, 23, 59)), at: at(11, 2, 12))
        try run(AssignmentAdd(course: robotics, title: "Lab5 보고서", due: at(11, 12, 23, 59)), at: at(11, 3, 12))
        try run(ExamAdd(course: graph, title: "기말고사", kind: .final, start: at(12, 1, 9), end: at(12, 1, 11), location: "A101"), at: setup)
    }
}
