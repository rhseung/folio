import FolioDomain
import Foundation
import PropertyBased
import Testing

struct MaterialIntakeTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    static let device = UUID()
    // 서울 기준 2026-10-01 목요일 14:00이다.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 14))!
    static let places = MaterialIntake.places(assignmentFolders: ["HW01", "HW02", "HW03", "Lab02"]) + ["Exams/중간고사", "Exams/기말고사"]

    static func session(week: Int, day: Int, hour: Int = 10, cancelled: Bool = false) -> Session {
        var s = Session(
            device: device, at: now, week: week, date: calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!)
        s.isCancelled = cancelled
        return s
    }

    // 4주차 화목, 5주차 화, 오늘 밤 수업이다(10/1은 9월부터 세면 31일째).
    static let sessions = [
        session(week: 4, day: 22), session(week: 4, day: 24), session(week: 5, day: 29), session(week: 5, day: 31, hour: 19),
        session(week: 6, day: 36),
    ]

    static func day(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10))! }

    static let exams = [
        Exam(device: device, at: now, title: "기말고사", start: day(12, 15), folder: "기말고사"),
        Exam(device: device, at: now, title: "중간고사", start: day(10, 20), folder: "중간고사"),
    ]

    func guess(
        _ name: String, pages: Int? = nil, landscape: Bool = false, settings: Settings = Settings(), exams: [Exam] = Self.exams,
        now: Date = Self.now
    ) -> IntakeGuess {
        MaterialIntake.guess(
            IncomingFile(name: name, pages: pages, landscape: landscape), places: Self.places, sessions: Self.sessions, exams: exams,
            now: now, settings: settings, calendar: Self.calendar)
    }

    @Test func aWeekInTheNameIsALectureForThatWeek() {
        let g = guess("04_Trees.pdf")
        #expect(g.folder == "Lectures" && g.why == .named("04_"))

        #expect(g.session == Self.sessions[1].id && g.sessionWhy == .week(4))
        let lecture = guess("GT_Lecture 5 - Matchings.pdf")
        #expect(lecture.why == .named("Lecture 5") && lecture.session == Self.sessions[3].id)
        #expect(guess("6주차 흐름.pdf").why == .named("6주차"))

        #expect(guess("6주차 흐름.pdf").session == Self.sessions[4].id)

        #expect(guess("09_Coloring.pdf").session == nil && guess("09_Coloring.pdf").sessionWhy == nil)
    }

    @Test func slidesWithoutAWeekGoToTodaysClass() {
        let g = guess("Matchings.pdf", pages: 24, landscape: true)
        #expect(g.folder == "Lectures" && g.why == .slides(pages: 24))
        #expect(g.session == Self.sessions[3].id && g.sessionWhy == .today)
    }

    @Test func namesPointAtTheirFolders() {
        #expect(guess("HW3.pdf") == IntakeGuess(folder: "Assignments/HW03", why: .named("HW3")))
        #expect(guess("gt_hw_2_solution.pdf").folder == "Assignments/HW02")

        #expect(guess("Lab 2 report.pdf").folder == "Assignments/Lab02")
        #expect(
            guess("Lab 2 manual.pdf")
                == IntakeGuess(folder: "Lectures", why: .named("manual"), session: Self.sessions[3].id, sessionWhy: .today))
        #expect(guess("실험 안내 3.pdf").folder == "Lectures")

        #expect(guess("HW9.pdf").folder == "Lectures" && guess("HW9.pdf").why == nil)
        #expect(guess("2024 중간고사 기출.pdf") == IntakeGuess(folder: "Inherited", why: .named("기출")))
        #expect(guess("GT_Syllabus_2026.pdf").folder == "Syllabus")
        #expect(guess("Midterm seating.pdf").folder == "Exams/중간고사")
        #expect(guess("기말 자리 배치.pdf").folder == "Exams/기말고사")
    }

    @Test func anUnnamedExamNoticeGoesToTheNextExam() {
        #expect(guess("seating.pdf").folder == "Exams/중간고사")
        #expect(guess("seating.pdf", now: Self.day(11, 2)).folder == "Exams/기말고사")
        #expect(guess("시험 안내.pdf", now: Self.day(12, 20)).folder == "Exams/기말고사")
        let undated = Self.exams.map {
            var e = $0; e.start = nil; return e
        }
        #expect(guess("seating.pdf", exams: undated).why == nil)
        #expect(guess("Introduction to Graph Theory.pdf").folder == "Textbooks")
        #expect(guess("Exercise 3.pdf").folder == "Exercises")
    }

    @Test func aLongPortraitFileIsABook() {
        #expect(guess("Diestel GT 5th.pdf", pages: 447) == IntakeGuess(folder: "Textbooks", why: .book(pages: 447)))
        #expect(guess("scan.pdf", pages: 3).why == nil)
    }

    // 하루 경계 전까지는 전 공부일이 이어지므로, 03:00에는 전날 저녁 수업이 "오늘"이다.
    @Test func todayFollowsTheDayBoundary() {
        let evening = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 21))!
        let tonight = [Session(device: Self.device, at: evening, week: 5, date: evening)]
        let at = { (hour: Int, day: Int) in
            MaterialIntake.guess(
                IncomingFile(name: "a.pdf"), places: Self.places, sessions: tonight,
                now: Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!,
                settings: Settings(dayBoundaryMinutes: 4 * 60), calendar: Self.calendar
            ).sessionWhy
        }
        #expect(at(3, 2) == .today)
        #expect(at(5, 2) == .latest)
    }

    @Test func planNumbersRepeatsAndMarksWhatItAdds() {
        let s = Self.sessions[2]
        let plan = MaterialIntake.plan(
            [
                ("Matchings.pdf", "Lectures", s), ("Matchings.pdf", "Lectures", s), ("hw.pdf", "Assignments/HW01", s),
                ("05-2_Hall.pdf", "Lectures", s),
            ],
            taken: { $0 == "Assignments/HW01" ? ["hw.pdf"] : [] })
        #expect(
            plan.map(\.path) == [
                "Lectures/05_Matchings.pdf", "Lectures/05_Matchings 2.pdf", "Assignments/HW01/hw 2.pdf", "Lectures/05-2_Hall.pdf",
            ])
        #expect(plan.map(\.prefix) == ["05_", "05_", nil, nil])
        #expect(plan.map(\.suffix) == [nil, " 2", " 2", nil])
    }

    // MARK: Properties

    static let names = Gen.element(of: [
        "05_Slides.pdf", "05-2_Hall.pdf", "HW3.pdf", "hw 12.pdf", "Lecture 12.pdf", "기출.pdf", "notes", "Lab 2.pdf",
        "7주차.pdf", "Final seating.pdf", "seating.pdf", "Lab 2 manual.pdf", "crisp 2.pdf", "select 3.pdf", "", "5_x.pdf", "syllabus.pdf",
    ]).map { $0! }

    @Test func aGuessStaysAmongTheOfferedFoldersAndHeldClasses() async {
        await propertyCheck(
            input: Self.names, Gen.int(in: 1...600).optional, Gen.bool(), Gen.int(in: 0...(30 * 86_400)),
            Gen.int(in: 0...(8 * 60))
        ) { name, pages, landscape, offset, boundary in
            let sessions = Self.sessions.enumerated().map { i, s in i == 1 ? Self.session(week: s.week, day: 24, cancelled: true) : s }
            let g = MaterialIntake.guess(
                IncomingFile(name: name, pages: pages, landscape: landscape), places: Self.places, sessions: sessions,
                exams: Self.exams,
                now: Self.now.addingTimeInterval(Double(offset) - 15 * 86_400),
                settings: Settings(dayBoundaryMinutes: boundary), calendar: Self.calendar)
            #expect(g.folder == "Lectures" || Self.places.contains(g.folder))
            #expect(g.folder == "Lectures" || g.session == nil)
            if let id = g.session { #expect(sessions.contains { $0.id == id && !$0.isCancelled }) }
            #expect((g.session == nil) == (g.sessionWhy == nil))
            if case .week(let week)? = g.sessionWhy { #expect(sessions.first { $0.id == g.session }?.week == week) }
        }
    }

    @Test func aPlanNeverOverwritesOrCollides() async {
        let item = zip(
            Gen.element(of: ["a.pdf", "a 2.pdf", "05_a.pdf", "code"]).map { $0! },
            Gen.element(of: ["Lectures", "Study", "Assignments/HW01"]).map { $0! }, Gen.bool)
        let held = Gen.element(of: ["a.pdf", "05_a.pdf", "a 2.pdf", "code 2"]).map { $0! }.array(of: 0...3)
        await propertyCheck(input: item.array(of: 0...8), held) { items, held in
            let plan = MaterialIntake.plan(items.map { ($0.0, $0.1, $0.2 ? Self.sessions[2] : nil) }, taken: { _ in Set(held) })
            #expect(Set(plan.map(\.path)).count == plan.count)
            #expect(plan.allSatisfy { !held.contains($0.name) })
            for (p, i) in zip(plan, items) {
                #expect(p.folder == i.1)
                #expect((p.prefix != nil) == (i.1 == "Lectures" && i.2 && !StandardLayout.isLectureFileName(i.0)))
                #expect(p.name == (p.prefix ?? "") + MaterialIntake.freeName(i.0, taken: []).insertingSuffix(p.suffix))
            }
        }
    }
}

private extension String {
    func insertingSuffix(_ suffix: String?) -> String {
        guard let suffix else { return self }
        let ext = (self as NSString).pathExtension
        return ext.isEmpty ? self + suffix : (self as NSString).deletingPathExtension + suffix + "." + ext
    }
}
