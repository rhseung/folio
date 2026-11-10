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
        case .busyDay, .manyExams:
            // Before the slides are tracked, so the course holds this file's hash. Split into units below, they need
            // pages to open: a placeholder left the split screen and the section bars with nothing to show.
            try SampleLecture.write(to: folder.appending(path: Builder.graphFolder).appending(path: Builder.matchingSlides))
            try build.busyDay(extraExams: self == .manyExams)
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
    static let graphFolder = "2026-3/EC4207 그래프 이론"
    static let matchingSlides = "Lectures/05_Matchings.pdf"

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
            if !unfinished { try run(SessionSet(course: course, session: id, kind: .keep, skipsReview: .keep, reviewUnfinished: .set(false)), at: end) }
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
        let os = try run(CourseAdd(code: codes[0].id, number: "3204", title: "운영체제", credits: 3, mode: .relative, semester: fall), at: setup)
        let prob = try run(CourseAdd(code: codes[1].id, number: "2004", title: "확률과 통계", credits: 3, mode: .relative, semester: fall), at: setup)
        let physics = try run(CourseAdd(code: codes[2].id, number: "1102", title: "일반물리학", credits: 3, mode: .absolute, semester: fall), at: setup)
        let writing = try run(CourseAdd(code: codes[3].id, number: "1511", title: "글쓰기의 기초", credits: 2, mode: .passFail, semester: fall), at: setup)

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
        // A colloquium carries no credits and nothing to study, but still meets every week; graphite keeps it quiet.
        let colloquium = try run(CourseAdd(code: codes[3].id, number: "9331", title: "콜로퀴움", credits: 0, mode: .passFail, semester: fall), at: setup)
        try run(CourseSet(course: colloquium, fields: [.schedule(slots([3], 1050, 1110, "Lecture Hall")), .color(CourseColor.neutral)]), at: setup)

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
        try recording(graph, session: s(graph, 11, 2), start: at(11, 2, 9))
        let coloring = try unit(graph, "그래프 채색", [s(graph, 10, 26), s(graph, 10, 28)], at: at(10, 28, 11))
        try lectureSections(graph, matching: matching, classes: [s(graph, 10, 19), s(graph, 10, 21), s(graph, 11, 2)])
        let scheduling = try unit(os, "프로세스 스케줄링", [s(os, 10, 19), s(os, 10, 21)], at: at(10, 21, 15))
        _ = try unit(os, "교착 상태", [s(os, 10, 26)], at: at(10, 26, 15))
        let conditional = try unit(prob, "조건부 확률", [s(prob, 10, 26), s(prob, 10, 28)], at: at(10, 28, 16))
        // A Friday evening makeup, off the timetable, so the class in session today has one on its page.
        let makeup = try run(SessionAdd(course: robotics, date: at(10, 30, 19), end: at(10, 30, 20, 15), kind: .makeup), at: at(10, 28, 12))
        try run(SessionNote(course: robotics, session: makeup, kind: .review), at: at(10, 30, 21))
        try run(SessionSet(course: robotics, session: makeup, reviewUnfinished: .set(false)), at: at(10, 30, 21))
        let kinematics = try unit(robotics, "순기구학", [s(robotics, 10, 21), s(robotics, 10, 26), makeup], at: at(10, 26, 12))
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
        // Repeats of each kind, for the assignment list's labels.
        let repeats: [String: AssignmentRepeat] = ["HW6": .biweekly, "HW5": .weekly, "SP2": AssignmentRepeat(.week, weekdays: [1, 3]),
                                                   "HW4": AssignmentRepeat(every: 3, .day),
                                                   "Lab5 보고서": AssignmentRepeat(.week, weekdays: [1, 3])]
        for (course, title, due, status) in deadlines {
            let id = try run(AssignmentAdd(course: course, title: title, due: due, repeats: repeats[title]), at: at(10, 20, 9))
            if status != .todo { try run(AssignmentStatusSet(course: course, assignment: id, status: status), at: at(11, 3, 20)) }
        }

        let quiz = try run(ExamAdd(course: prob, title: "Quiz 3", start: at(11, 6, 14, 30), end: at(11, 6, 15), location: "A203"), at: setup)
        try run(ExamAdd(course: physics, title: "2차 시험", start: at(11, 13, 19), end: at(11, 13, 21), location: "Physics 101"), at: setup)
        try run(ExamAdd(course: os, title: "기말고사", start: at(12, 2, 13), end: at(12, 2, 15), location: "B115"), at: setup)
        try run(ExamAdd(course: graph, title: "기말고사", start: at(12, 14, 9), end: at(12, 14, 11), location: "A101"), at: setup)
        if extraExams {
            try run(ExamAdd(course: writing, title: "에세이 발표", start: at(11, 11, 19), end: at(11, 11, 21), location: "N210"), at: setup)
            try run(ExamAdd(course: robotics, title: "중간 발표", start: at(11, 18, 10, 30), end: at(11, 18, 12), location: "C204"), at: setup)
            try run(ExamAdd(course: graph, title: "Quiz 4", start: at(11, 25, 9), end: at(11, 25, 9, 30), location: "A101"), at: setup)
        }
        try run(ExamPlanAdd(course: prob, exam: quiz, title: "조건부 확률 연습문제 풀기", day: LocalDate(at(11, 4), in: Scenario.calendar), unit: conditional), at: at(11, 1, 10))
    }

    /// Monday's class recorded with the slides open, so its replay has a transcript and the pages it was on. The audio
    /// isn't written: a fixture has no sound to play, and the player shows the length the recording kept.
    func recording(_ course: UUID, session: UUID, start: Date) throws {
        try run(MaterialTrack(course: course), at: start)
        let ctx = ActionContext(gist: gist, device: device, now: start, calendar: Scenario.calendar)
        let store = try ctx.store(course)
        guard let slides = try ctx.file(course).materials.first(where: { $0.path.hasPrefix("Lectures/") }) else { return }
        let lines: [(Int, String)] = [
            (0, "지난 시간에 이분 그래프에서 최대 매칭을 정의했습니다."), (95, "오늘은 홀의 정리를 증명하고 시작하겠습니다."),
            (240, "집합 S의 이웃 N(S)가 S보다 작으면 S를 모두 짝지을 수 없겠죠."), (410, "그 반대가 성립한다는 것이 홀의 정리입니다."),
            (620, "증명은 S의 크기에 대한 귀납법으로 합니다."), (905, "여기서 경우를 둘로 나눕니다."),
            (1180, "이제 증가 경로를 봅시다. 매칭에 들지 않은 꼭짓점에서 시작해서"), (1420, "매칭 간선과 아닌 간선을 번갈아 지나는 경로입니다."),
            (1700, "베르주의 정리: 최대 매칭이 아니면 증가 경로가 있다."), (2050, "이 정리가 헝가리안 방법의 바탕입니다."),
            (2380, "쾨니그의 정리로 넘어가면, 이분 그래프에서 최대 매칭의 크기는"), (2610, "최소 꼭짓점 덮개의 크기와 같습니다."),
            (3020, "과제 5번에 이것을 쓰는 문제가 있습니다."), (3400, "다음 시간에는 일반 그래프의 매칭, 터트의 정리를 봅니다."),
        ]
        let transcript = LectureTranscript(locale: "ko-KR", lines: zip(lines, lines.dropFirst().map(\.0) + [3700]).map { line, end in
            .init(start: TimeInterval(line.0), end: TimeInterval(end - 5), text: line.1)
        })
        let pages = [(0, 2), (230, 4), (600, 6), (1150, 9), (1690, 12), (2370, 15)].map { PageVisit(at: TimeInterval($0.0), materialId: slides.id, page: $0.1) }
        let recording = Recording(id: UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!, device: device, at: start, sessionId: session,
                                  file: "Recordings/11-02(월).m4a", duration: 4500, bookmarks: [1700, 2610], pages: pages)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        try store.saveTranscript(transcript, of: recording)
        try ctx.edit(course) { $0.recordings.append(recording) }
    }

    /// The matching slides split into the chapter's units (#321), two of them new under it, and the classes' pages
    /// through the file, so the section bars and strips have something to draw.
    func lectureSections(_ course: UUID, matching: UUID, classes: [UUID]) throws {
        let ctx = ActionContext(gist: gist, device: device, now: at(10, 21, 12), calendar: Scenario.calendar)
        guard let slides = try ctx.file(course).materials.first(where: { $0.path == Self.matchingSlides })?.id else { return }
        try run(MaterialSplit(course: course, material: slides, sections: [
            LectureCut(unit: matching, firstPage: 1, lastPage: 8),
            LectureCut(unit: UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!, title: "Hall의 정리", parent: matching, firstPage: 9, lastPage: 16),
            LectureCut(unit: UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!, title: "증가 경로", parent: matching, firstPage: 17, lastPage: 24),
        ]), at: at(10, 21, 12))
        for (session, pages) in zip(classes, [1...7, 8...13, 14...20]) {
            try run(MaterialLinkSession(course: course, material: slides, session: session, linked: true, firstPage: pages.lowerBound, lastPage: pages.upperBound), at: at(11, 2, 11))
        }
        // The last class reached both new units; its row has no title naming them, so it draws the strip.
        for unit in ["B0000000-0000-4000-8000-000000000002", "B0000000-0000-4000-8000-000000000003"] {
            try run(UnitLink(course: course, unit: UUID(uuidString: unit)!, sessions: [classes[2]]), at: at(11, 2, 11))
        }
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
        try run(ExamAdd(course: graph, title: "기말고사", start: at(12, 1, 9), end: at(12, 1, 11), location: "A101"), at: setup)
    }
}
