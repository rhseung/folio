import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation

public enum Scenario: String, CaseIterable, Sendable {
    case busyDay
    case manyExams
    case quietDay
    case empty

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
            // 과목이 이 파일의 hash를 갖도록 슬라이드를 추적하기 전에 쓴다. 아래에서 단원으로 나누므로 열 수 있는 쪽이
            // 필요하다. 자리표시자로는 나누기 화면과 구간 막대에 보일 것이 없었다.
            try SampleLecture.write(to: folder.appending(path: Builder.graphFolder).appending(path: Builder.matchingSlides))
            try SampleSheet.write(to: folder.appending(path: Builder.graphFolder).appending(path: Builder.midtermSheet))
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
    static let midtermSheet = "Inherited/소순범/2024 Midterm.pdf"

    func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { Scenario.at(2026, m, d, h, min) }

    @discardableResult
    func run(_ action: some Action, at now: Date) throws -> UUID {
        let ctx = ActionContext(gist: gist, device: device, now: now, calendar: Scenario.calendar)
        try action.run(ctx)
        return ctx.made ?? UUID()
    }

    func slots(_ weekdays: [Int], _ start: Int, _ end: Int, _ room: String) -> [ClassTime] {
        weekdays.map { ClassTime(weekday: $0, startMinute: start, endMinute: end, room: room) }
    }

    @discardableResult
    func session(_ course: UUID, _ date: Date, minutes: Int = 75, note: Bool = true, unfinished: Bool = false) throws -> UUID {
        let id = try run(SessionAdd(course: course, date: date), at: date)
        if note {
            let end = date.addingTimeInterval(TimeInterval(minutes * 60))
            try run(SessionNote(course: course, session: id, kind: .review), at: end)
            if !unfinished {
                try run(SessionSet(course: course, session: id, kind: .keep, skipsReview: .keep, reviewUnfinished: .set(false)), at: end)
            }
        }
        return id
    }

    // 공부 시간은 앱이 화면을 본 시간을 적는 줄이라 액션이 없다. 오늘 화면의 공부 시간 막대가 비지 않게 같은 줄을 직접 쓴다.
    func studied(_ course: UUID, _ start: Date, minutes: Int) throws {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let ctx = ActionContext(gist: gist, device: device, now: end, calendar: Scenario.calendar)
        try ctx.log(StudySessionEvent(courseId: course, start: start, end: end, screen: "course"), course: course, at: end)
    }

    func unit(_ course: UUID, _ title: String, _ sessions: [UUID], at date: Date) throws -> UUID {
        let id = try run(UnitAdd(course: course, title: title), at: date)
        try run(UnitLink(course: course, unit: id, sessions: sessions), at: date)
        return id
    }

    // 그래프 이론의 족보 한 부를 풀고 카드를 넘긴 기록이다. 매칭은 다 했지만 다시 확인할 문제가 남았고, 그래프 채색은 틀린
    // 문제가 있어 부족으로 보인다.
    func practice(_ course: UUID, matching: UUID, coloring: UUID, exam: UUID) throws {
        let made = at(10, 30, 20)
        func problem(_ n: String, _ text: String, _ format: ProblemFormat, _ answer: String?, _ unit: UUID, page: Int) -> Problem {
            Problem(
                number: n, page: page, text: text, format: format, answer: answer, unitIds: [unit],
                solution: answer.map { format == .trueFalse ? "The statement is \($0 == "참" ? "true" : "false")." : "The answer is \($0)." }
            )
        }
        let problems = [
            problem("1", "Find the size of a maximum matching in $K_{3,3}$.", .short, "3", matching, page: 1),
            problem("2", "Every regular bipartite graph has a perfect matching.", .trueFalse, "참", matching, page: 1),
            problem("3", "Prove Hall's theorem.", .written, nil, matching, page: 2),
            problem(
                "4", "Using Berge's theorem, show that a matching with no augmenting path is maximum.", .written, nil, matching, page: 2),
            problem("5", "Find the chromatic number of the Petersen graph.", .short, "3", coloring, page: 3),
            problem("6", "Every planar graph is 4-colorable.", .trueFalse, "참", coloring, page: 3),
            problem("7", "State the hypotheses of Brooks' theorem.", .written, nil, coloring, page: 4),
        ]
        let set = try run(ProblemSetAdd(course: course, title: "2025 기말", source: .pastExam, problems: problems), at: made)
        func solve(_ i: Int, _ verdict: Verdict, _ basis: GradeBasis, at date: Date, reason: WrongReason? = nil) throws {
            try run(
                ProblemSolve(course: course, set: set, problem: problems[i].id, verdict: verdict, basis: basis, reason: reason), at: date)
        }
        try solve(0, .correct, .key, at: at(11, 1, 14))
        try solve(1, .correct, .key, at: at(11, 1, 14, 5))
        try solve(2, .partial, .claude, at: at(11, 1, 14, 30), reason: .method)
        try solve(2, .correct, .claude, at: at(11, 1, 15))
        try solve(3, .correct, .solution, at: at(11, 3, 21))
        try solve(4, .wrong, .key, at: at(11, 3, 22), reason: .concept)
        try solve(5, .correct, .key, at: at(11, 3, 22, 5))
        try run(UnitDone(course: course, unit: matching), at: at(11, 3, 23))

        let cards = [
            StudyCard(device: device, at: made, unitId: matching, front: "증가 경로", back: "매칭에 들지 않은 두 꼭짓점을 잇고 매칭 간선과 아닌 간선을 번갈아 지나는 경로"),
            StudyCard(device: device, at: made, unitId: matching, front: "홀의 조건", back: "모든 $S \\subseteq X$에 대해 $|N(S)| \\ge |S|$"),
            StudyCard(device: device, at: made, unitId: coloring, front: "채색수", back: "인접한 꼭짓점이 다른 색이 되도록 칠하는 데 필요한 최소 색 수"),
        ]
        try run(CardSave(course: course, cards: cards), at: made)
        try run(CardFlip(course: course, unit: matching, card: cards[0].id), at: at(11, 2, 21))
        try run(CardFlip(course: course, unit: matching, card: cards[1].id, known: false), at: at(11, 2, 21, 2))

        let ctx = ActionContext(gist: gist, device: device, now: made, calendar: Scenario.calendar)
        if let slides = try ctx.file(course).materials.first(where: { $0.path == Self.matchingSlides }) {
            for page in 1...8 { try run(MaterialViewed(course: course, material: slides.id, page: page), at: at(11, 1, 13)) }
        }
        try plan(course, exam: exam, matching: matching)

        // 2024 중간고사는 Claude가 뽑아 둔 초안으로 남아 문제 페이지에 알림 카드가 뜬다. 뽑은 문제와 풀이는 문제지의 언어와 상관없이 영어다.
        if let sheet = try ctx.file(course).materials.first(where: { $0.path == Self.midtermSheet }) {
            var drafted = [
                problem("1", "Is the graph $K_{3,3}$ below planar? Answer true or false.", .trueFalse, "거짓", coloring, page: 1),
                problem("2a", "State Hall's theorem.", .written, nil, matching, page: 2),
                problem("2b", "Use it to decide whether $G$ has a perfect matching.", .written, nil, matching, page: 2),
                problem("3", "Find the chromatic number of the Petersen graph.", .short, "3", coloring, page: 3),
            ]
            drafted[0].figures = SampleSheet.planarFigure.map { [$0] } ?? []
            drafted[1].parent = "2"
            drafted[2].parent = "2"
            let stem = ProblemGroup(
                number: "2", page: 2, text: "Let $G$ be the bipartite graph below.", figures: SampleSheet.bipartiteFigure.map { [$0] } ?? []
            )
            try run(ProblemSetPropose(course: course, material: sheet.id, problems: drafted, groups: [stem]), at: at(11, 4, 9))
        }
    }

    func busyDay(extraExams: Bool = false) throws {
        let setup = at(8, 28, 10)
        let codes = ["EC", "MA", "PS", "GS"].map { CourseCode(device: device, at: setup, prefix: $0) }
        // 저장소가 공개이므로 등급 체계, 분류, 사람은 모두 지어낸 것이다. 실제 성적이나 사람은 없다.
        let grades =
            [("A+", 4.5), ("A0", 4.0), ("B+", 3.5), ("B0", 3.0), ("C+", 2.5), ("C0", 2.0), ("D+", 1.5), ("D0", 1.0), ("F", 0.0)]
            .map { LetterGrade(device: device, at: setup, symbol: $0.0, points: $0.1, countsInGpa: true, countsInCredits: $0.0 != "F") }
            + [LetterGrade(device: device, at: setup, symbol: "S", points: nil, countsInGpa: false, countsInCredits: true)]
        let major = Category(device: device, at: setup, name: "전공", group: "전공", isMajor: true, minCredits: 36)
        let science = Category(device: device, at: setup, name: "기초과학", group: "기초", minCredits: 30)
        let humanities = Category(device: device, at: setup, name: "인문사회", group: "교양", minCredits: 24)
        let people = [
            Person(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!, device: device, at: setup, name: "김도윤",
                email: "doyun@example.com", office: "A동 412", officeHours: "화 14:00-16:00"),
            Person(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!, device: device, at: setup, name: "이서연",
                email: "seoyeon@example.com", office: "C동 301", officeHours: "목 10:00-11:00"),
            Person(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!, device: device, at: setup, name: "박준호",
                email: "junho@example.com", role: .lecturer, office: "B동 208"),
            Person(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!, device: device, at: setup, name: "최하은",
                email: "haeun@example.com", role: .assistant, office: "A동 405", memo: "그래프 이론 조교"),
        ]
        try run(
            CatalogSet(catalog: Catalog(codes: codes, categories: [major, science, humanities], letterGrades: grades, people: people)),
            at: setup)
        let os = try run(
            CourseAdd(code: codes[0].id, number: "3204", title: "운영체제", credits: 3, mode: .relative, semester: fall), at: setup)
        let prob = try run(
            CourseAdd(code: codes[1].id, number: "2004", title: "확률과 통계", credits: 3, mode: .relative, semester: fall), at: setup)
        let physics = try run(
            CourseAdd(code: codes[2].id, number: "1102", title: "일반물리학", credits: 3, mode: .absolute, semester: fall), at: setup)
        let writing = try run(
            CourseAdd(code: codes[3].id, number: "1511", title: "글쓰기의 기초", credits: 2, mode: .passFail, semester: fall), at: setup)

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
        let colloquium = try run(
            CourseAdd(code: codes[3].id, number: "9331", title: "콜로퀴움", credits: 0, mode: .passFail, semester: fall), at: setup)
        try run(
            CourseSet(course: colloquium, fields: [.schedule(slots([3], 1050, 1110, "Lecture Hall")), .color(CourseColor.neutral)]),
            at: setup)

        let staffed: [(UUID, [UUID], FolioDomain.Category)] = [
            (graph, [people[0].id, people[3].id], major), (robotics, [people[1].id], major), (os, [people[2].id], major),
            (prob, [people[2].id], science), (physics, [], science), (writing, [], humanities), (linearAlgebra, [people[0].id], science),
        ]
        for (course, instructors, category) in staffed {
            try run(CourseSet(course: course, fields: [.instructors(instructors), .categories([category.id])]), at: setup)
        }
        try run(CourseSet(course: linearAlgebra, fields: [.finalGrade(grades[1].id)]), at: at(6, 30, 12))
        try gradeBook(graph, at: setup)

        var held: [UUID: [Date: UUID]] = [:]
        for (course, schedule, _) in timetable {
            for day in [at(10, 19), at(10, 21), at(10, 26), at(10, 28), at(11, 2), at(11, 4)] {
                let weekday = Scenario.calendar.isoWeekday(of: day)
                guard let slot = schedule.first(where: { $0.weekday == weekday }) else { continue }
                let start = day.addingTimeInterval(TimeInterval(slot.startMinute * 60))
                let today = day == at(11, 4)
                let thisWeek = day >= at(11, 2)
                held[course, default: [:]][day] = try session(
                    course, start, minutes: slot.endMinute - slot.startMinute,
                    note: !today && (!thisWeek || course == physics), unfinished: course == physics && thisWeek)
            }
        }
        func s(_ course: UUID, _ m: Int, _ d: Int) -> UUID { held[course]![at(m, d)]! }

        let matching = try unit(graph, "매칭", [s(graph, 10, 19), s(graph, 10, 21)], at: at(10, 21, 11))
        try recording(graph, session: s(graph, 11, 2), start: at(11, 2, 9))
        let coloring = try unit(graph, "그래프 채색", [s(graph, 10, 26), s(graph, 10, 28)], at: at(10, 28, 11))
        try lectureSections(graph, matching: matching, classes: [s(graph, 10, 19), s(graph, 10, 21), s(graph, 11, 2)])
        _ = try unit(os, "프로세스 스케줄링", [s(os, 10, 19), s(os, 10, 21)], at: at(10, 21, 15))
        _ = try unit(os, "교착 상태", [s(os, 10, 26)], at: at(10, 26, 15))
        _ = try unit(prob, "조건부 확률", [s(prob, 10, 26), s(prob, 10, 28)], at: at(10, 28, 16))
        let makeup = try run(SessionAdd(course: robotics, date: at(10, 30, 19), end: at(10, 30, 20, 15), kind: .makeup), at: at(10, 28, 12))
        try run(SessionNote(course: robotics, session: makeup, kind: .review), at: at(10, 30, 21))
        try run(SessionSet(course: robotics, session: makeup, reviewUnfinished: .set(false)), at: at(10, 30, 21))
        _ = try unit(robotics, "순기구학", [s(robotics, 10, 21), s(robotics, 10, 26), makeup], at: at(10, 26, 12))
        _ = try unit(robotics, "역기구학과 야코비안", [s(robotics, 10, 28)], at: at(10, 28, 12))
        _ = try unit(physics, "전기장과 가우스 법칙", [s(physics, 10, 26), s(physics, 10, 28)], at: at(10, 28, 18))

        try studied(graph, at(10, 23, 21), minutes: 40)
        try studied(os, at(10, 30, 20), minutes: 55)
        try studied(graph, at(11, 1, 14), minutes: 30)
        try studied(robotics, at(11, 2, 21), minutes: 45)
        try studied(prob, at(11, 3, 22), minutes: 35)
        try studied(graph, at(11, 4, 8), minutes: 25)

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
        let repeats: [String: AssignmentRepeat] = [
            "HW6": .biweekly, "HW5": .weekly, "SP2": AssignmentRepeat(.week, weekdays: [1, 3]),
            "HW4": AssignmentRepeat(every: 3, .day),
            "Lab5 보고서": AssignmentRepeat(.week, weekdays: [1, 3]),
        ]
        for (course, title, due, status) in deadlines {
            let id = try run(AssignmentAdd(course: course, title: title, due: due, repeats: repeats[title]), at: at(10, 20, 9))
            if status != .todo { try run(AssignmentStatusSet(course: course, assignment: id, status: status), at: at(11, 3, 20)) }
        }

        // 마감 지난 과제와 늦게 낸 과제다. 로봇공학에만 지각 규칙이 있어 "지금 내면 최대" 줄은 그 과목에만 보인다. 렌더가 그리는
        // 과목 화면이 로봇공학이라 그 과목에 둔다.
        try run(
            PolicySet(course: robotics, latePolicy: .set("하루 10% 감점, 3일이 지나면 받지 않음"), lateRule: .set(LateRule(percentPerDay: 10, days: 3))),
            at: setup)
        let late = try run(AssignmentAdd(course: robotics, title: "Lab3 보고서", due: at(10, 19, 23, 59)), at: at(10, 13, 9))
        try run(
            AssignmentStatusSet(course: robotics, assignment: late, status: .submitted, submittedAt: at(10, 20, 10)), at: at(10, 20, 10))
        try run(AssignmentAdd(course: robotics, title: "Lab4 보고서", due: at(11, 2, 23, 59)), at: at(10, 27, 9))
        try run(AssignmentAdd(course: prob, title: "HW5", due: at(11, 3, 23, 59)), at: at(10, 27, 9))

        let quiz = try run(
            ExamAdd(course: prob, title: "Quiz 3", start: at(11, 6, 14, 30), end: at(11, 6, 15), location: "A203"), at: setup)
        try run(ExamAdd(course: physics, title: "2차 시험", start: at(11, 13, 19), end: at(11, 13, 21), location: "Physics 101"), at: setup)
        try run(ExamAdd(course: os, title: "기말고사", start: at(12, 2, 13), end: at(12, 2, 15), location: "B115"), at: setup)
        let graphFinal = try run(
            ExamAdd(course: graph, title: "기말고사", start: at(12, 14, 9), end: at(12, 14, 11), location: "A101"), at: setup)
        for unit in [matching, coloring] { try run(ExamScope(course: graph, exam: graphFinal, unit: unit), at: setup) }
        try practice(graph, matching: matching, coloring: coloring, exam: graphFinal)
        if extraExams {
            try run(ExamAdd(course: writing, title: "에세이 발표", start: at(11, 11, 19), end: at(11, 11, 21), location: "N210"), at: setup)
            try run(ExamAdd(course: robotics, title: "중간 발표", start: at(11, 18, 10, 30), end: at(11, 18, 12), location: "C204"), at: setup)
            try run(ExamAdd(course: graph, title: "Quiz 4", start: at(11, 25, 9), end: at(11, 25, 9, 30), location: "A101"), at: setup)
        }
        try run(
            ExamPlanAdd(course: prob, exam: quiz, title: "조건부 확률 연습문제 풀기", day: LocalDate(at(11, 4), in: Scenario.calendar)),
            at: at(11, 1, 10))
    }

    // 기말 정리 노트 셋을 11/3부터 사흘에 놓고 그 뒤에 모의고사를 둔다. 첫 노트는 정독만 끝내서 오늘(11/4)에 밀린 단계가
    // 보이고, 그래프 채색은 정리 노트가 없어 노트 만들기가 놓인다.
    func plan(_ course: UUID, exam: UUID, matching: UUID) throws {
        let made = at(11, 2, 20)
        guard let hall = UUID(uuidString: "B0000000-0000-4000-8000-000000000002"),
            let paths = UUID(uuidString: "B0000000-0000-4000-8000-000000000003")
        else { return }
        let basics = try run(
            NoteAdd(
                course: course, title: "기말 01 매칭의 기초", kind: .unit,
                body: "# 매칭의 기초\n\n> [!definition] 매칭\n> 공통 끝점이 없는 간선의 집합이다.\n", units: [matching]), at: made)
        try run(
            NoteAdd(
                course: course, title: "기말 02 홀의 정리", kind: .unit,
                body:
                    "# 홀의 정리\n\n> [!theorem] Hall\n> 이분 그래프에 $X$를 모두 덮는 매칭이 있을 필요충분조건은 모든 $S \\subseteq X$에 대해 $|N(S)| \\ge |S|$인 것이다.\n\n> [!proof]\n> $|X|$에 대한 귀납법으로 보인다.\n",
                units: [hall]), at: made)
        try run(
            NoteAdd(
                course: course, title: "기말 03 증가 경로", kind: .unit,
                body: "# 증가 경로\n\n> [!theorem] Berge\n> 매칭이 최대일 필요충분조건은 증가 경로가 없는 것이다.\n", units: [paths]), at: made)

        let start = LocalDate(at(11, 3), in: Scenario.calendar)
        try run(ExamPlanMake(course: course, exam: exam, start: start, end: start.adding(days: 2), after: .mock), at: at(11, 3, 9))
        let ctx = ActionContext(gist: gist, device: device, now: at(11, 3, 21), calendar: Scenario.calendar)
        let read = try ctx.file(course).exams.first { $0.id == exam }?.plan.first { $0.target == .note(basics, .read) }
        if let read { try run(ExamPlanCheck(course: course, items: [read.id]), at: at(11, 3, 21)) }
    }

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
        let transcript = LectureTranscript(
            locale: "ko-KR",
            lines: zip(lines, lines.dropFirst().map(\.0) + [3700]).map { line, end in
                .init(start: TimeInterval(line.0), end: TimeInterval(end - 5), text: line.1)
            })
        let pages = [(0, 2), (230, 4), (600, 6), (1150, 9), (1690, 12), (2370, 15)].map {
            PageVisit(at: TimeInterval($0.0), materialId: slides.id, page: $0.1)
        }
        let recording = Recording(
            id: UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!, device: device, at: start, sessionId: session,
            file: "Recordings/11-02(월).m4a", duration: 4500, bookmarks: [1700, 2610], pages: pages)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        try store.saveTranscript(transcript, of: recording)
        try ctx.edit(course) { $0.recordings.append(recording) }
    }

    func lectureSections(_ course: UUID, matching: UUID, classes: [UUID]) throws {
        let ctx = ActionContext(gist: gist, device: device, now: at(10, 21, 12), calendar: Scenario.calendar)
        guard let slides = try ctx.file(course).materials.first(where: { $0.path == Self.matchingSlides })?.id else { return }
        try run(
            MaterialSplit(
                course: course, material: slides,
                sections: [
                    LectureCut(unit: matching, firstPage: 1, lastPage: 8),
                    LectureCut(
                        unit: UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!, title: "Hall의 정리", parent: matching, firstPage: 9,
                        lastPage: 16),
                    LectureCut(
                        unit: UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!, title: "증가 경로", parent: matching, firstPage: 17,
                        lastPage: 24),
                ]), at: at(10, 21, 12))
        for (session, pages) in zip(classes, [1...7, 8...13, 14...20]) {
            try run(
                MaterialLinkSession(
                    course: course, material: slides, session: session, linked: true, firstPage: pages.lowerBound,
                    lastPage: pages.upperBound), at: at(11, 2, 11))
        }
        for unit in ["B0000000-0000-4000-8000-000000000002", "B0000000-0000-4000-8000-000000000003"] {
            try run(UnitLink(course: course, unit: UUID(uuidString: unit)!, sessions: [classes[2]]), at: at(11, 2, 11))
        }
    }

    func gradeBook(_ course: UUID, at setup: Date) throws {
        let homework = try run(ComponentAdd(course: course, name: "과제", weight: 30, expectedCount: 6), at: setup)
        let quizzes = try run(
            ComponentAdd(course: course, name: "퀴즈", weight: 20, aggregation: .dropLowest(1), expectedCount: 5), at: setup)
        let midterm = try run(ComponentAdd(course: course, name: "중간고사", weight: 25, aggregation: .single), at: setup)
        try run(ComponentAdd(course: course, name: "기말고사", weight: 25, aggregation: .single), at: setup)
        for (i, (score, day)) in [(9.0, at(9, 15)), (10, at(9, 29)), (7.5, at(10, 13)), (9, at(10, 27))].enumerated() {
            try run(
                ScoreAdd(
                    course: course, component: homework, title: "HW\(i + 1)", score: score, max: 10,
                    date: LocalDate(day, in: Scenario.calendar)), at: day)
        }
        for (i, (score, day)) in [(8.0, at(9, 22)), (5, at(10, 6)), (9, at(10, 20))].enumerated() {
            try run(
                ScoreAdd(
                    course: course, component: quizzes, title: "Quiz \(i + 1)", score: score, max: 10,
                    date: LocalDate(day, in: Scenario.calendar)), at: day)
        }
        try run(
            ScoreAdd(
                course: course, component: midterm, title: "중간고사", score: 72, max: 100, mean: 61.5, median: 59.5, stdDev: 12,
                date: LocalDate(at(10, 21), in: Scenario.calendar)), at: at(10, 23))
    }

    func quietDay() throws {
        let setup = at(8, 28, 10)
        try run(
            CourseSet(
                course: graph, fields: [.schedule(slots([1, 3], 540, 615, "A101")), .icon("point.3.connected.trianglepath.dotted")]),
            at: setup)
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
