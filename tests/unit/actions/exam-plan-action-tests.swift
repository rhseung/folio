import FolioActions
import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

// 그래프 이론에 범위 단원 셋(매칭, 채색, 평면 그래프)과 정리 노트 둘을 두고 12/14의 기말을 놓는다. 평면 그래프에는 정리 노트가 없다.
struct ExamPlanActionTests {
    static let course = ActionTests.graphTheory
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    let device = UUID()
    let gist: GISTStore
    let exam = UUID()
    let matching = UUID(), coloring = UUID(), planar = UUID()
    let hall = UUID(), brooks = UUID()

    static func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static func day(_ month: Int, _ day: Int) -> LocalDate {
        guard let date = LocalDate(year: 2026, month: month, day: day) else { preconditionFailure("\(month)/\(day)") }
        return date
    }

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let setup = Self.at(11, 20)
        try run(UnitAdd(id: matching, course: Self.course, title: "매칭"), at: setup)
        try run(UnitAdd(id: coloring, course: Self.course, title: "채색"), at: setup)
        try run(UnitAdd(id: planar, course: Self.course, title: "평면 그래프"), at: setup)
        try run(
            ExamAdd(id: exam, course: Self.course, title: "기말고사", start: Self.at(12, 14, 9), scope: [matching, coloring, planar]),
            at: setup)
        try run(
            NoteAdd(
                id: hall, course: Self.course, title: "기말 01 홀의 정리", kind: .unit,
                body: "# 홀의 정리\n\n> [!theorem] Hall\n> 조건을 만족하면 완전 매칭이 있다.\n", units: [matching]), at: setup)
        try run(
            NoteAdd(
                id: brooks, course: Self.course, title: "기말 02 채색수", kind: .unit,
                body: "# 채색수\n\n> [!definition] 채색수\n> 필요한 최소 색 수다.\n", units: [coloring]), at: setup)
    }

    @discardableResult
    func run(_ action: some Action, at now: Date) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, calendar: Self.calendar)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.course) }

    func planned() throws -> Exam { try #require(try file().exams.first { $0.id == exam }) }

    func item(_ target: ExamPlanTarget) throws -> ExamPlanItem {
        try #require(try planned().plan.first { $0.target == target && !$0.isRemoved })
    }

    func needsPlan(on now: Date) throws -> Bool {
        let ctx = ActionContext(gist: gist, device: device, now: now, calendar: Self.calendar)
        let file = try ctx.file(Self.course), settings = try ctx.settings()
        let e = try #require(file.exams.first { $0.id == exam })
        let proofs = ExamPlanProofs.read(file.examNotes(of: e), store: try ctx.store(Self.course), settings: settings)
        return file.needsPlan(
            e, proofs: proofs, today: settings.studyDay(of: now, calendar: Self.calendar), settings: settings, calendar: Self.calendar)
    }

    @Test func makingAPlanReadsTheNotesAndPlacesThemInThePeriod() throws {
        #expect(try needsPlan(on: Self.at(12, 8)))
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let e = try planned()
        #expect(e.planPeriod == ExamPlanPeriod(start: Self.day(12, 8), end: Self.day(12, 13)))
        // 정리 블록이 있는 홀의 정리만 증명을 받는다. 엿새에 노트 둘이라 12/8과 12/11이다.
        #expect(
            e.plan.map(\.target) == [
                .makeNote(planar), .note(hall, .read), .note(hall, .proof), .note(hall, .solve), .note(brooks, .read),
                .note(brooks, .solve),
            ])
        #expect(e.plan.map(\.day.day) == [8, 8, 8, 8, 11, 11])
        #expect(try !needsPlan(on: Self.at(12, 8)))
        // 공부일이 바뀌어도 다시 놓지 않는다.
        #expect(try !needsPlan(on: Self.at(12, 9)) && !needsPlan(on: Self.at(12, 12)))
    }

    @Test func aNoteThatGainsATheoremAsksForItsProofStage() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let before = try planned().plan
        try run(
            NoteWrite(
                course: Self.course, note: "Notes/기말 02 채색수.md",
                text: "# 채색수\n\n> [!theorem] Brooks\n> 완전 그래프와 홀수 순환이 아니면 채색수는 최대 차수 이하다.\n", expected: nil),
            at: Self.at(12, 9, 10))
        #expect(try needsPlan(on: Self.at(12, 9)))
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 9))
        let after = try planned().plan
        #expect(after.contains { $0.target == .note(brooks, .proof) })
        // 다시 놓아도 항목의 id는 그대로다.
        #expect(Set(before.map(\.id)).isSubset(of: Set(after.map(\.id))))
        #expect(try !needsPlan(on: Self.at(12, 9)))
    }

    @Test func aGivenPeriodIsStoredAndTheDaysAfterItTakeMockExams() throws {
        let past = [Problem(number: "1", unitIds: [matching])]
        try run(ProblemSetAdd(course: Self.course, title: "2025 기말", source: .pastExam, problems: past), at: Self.at(11, 21))
        try run(ProblemSetAdd(course: Self.course, title: "2024 기말", source: .pastExam, problems: past), at: Self.at(11, 21))
        try run(
            ExamPlanMake(course: Self.course, exam: exam, start: Self.day(12, 5), end: Self.day(12, 9), after: .mock), at: Self.at(12, 1))
        let e = try planned()
        #expect(e.planPeriod == ExamPlanPeriod(start: Self.day(12, 5), end: Self.day(12, 9), after: .mock))
        // 닷새에 노트 둘이라 12/5와 12/7이고, 족보가 둘이라 12/10과 12/11에 모의고사가 온다.
        #expect(e.plan.filter { $0.target.kind == .note }.map(\.day.day) == [5, 5, 5, 7, 7])
        #expect(e.plan.filter { $0.target == .mock }.map(\.day.day) == [10, 11])

        // 끝낼 날만 바꾸면 시작일과 기간 뒤는 그대로다.
        try run(ExamPlanMake(course: Self.course, exam: exam, end: Self.day(12, 6)), at: Self.at(12, 1))
        #expect(try planned().planPeriod == ExamPlanPeriod(start: Self.day(12, 5), end: Self.day(12, 6), after: .mock))
        #expect(try planned().plan.filter { $0.target == .mock }.map(\.day.day) == [7, 8])

        #expect(throws: ActionError.self) {
            try run(ExamPlanMake(course: Self.course, exam: exam, end: Self.day(12, 14)), at: Self.at(12, 1))
        }
        #expect(throws: ActionError.self) {
            try run(ExamPlanMake(course: Self.course, exam: exam, start: Self.day(12, 8)), at: Self.at(12, 1))
        }
    }

    @Test func puttingTheExamOffStretchesAPeriodThatEndedOnItsEve() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        try run(ExamSet(course: Self.course, exam: exam, start: .set(Self.at(12, 18, 9))), at: Self.at(12, 8, 13))
        #expect(try needsPlan(on: Self.at(12, 8, 14)))
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8, 14))
        // 손대지 않은 기간은 새 시험 전날까지 늘어난다. 열흘에 노트 둘이라 12/8과 12/13이다.
        #expect(try planned().planPeriod == ExamPlanPeriod(start: Self.day(12, 8), end: Self.day(12, 17)))
        #expect(try planned().plan.filter { $0.target.kind == .note }.map(\.day.day) == [8, 8, 8, 13, 13])
        #expect(try !needsPlan(on: Self.at(12, 8, 14)))

        // 일찍 끝내기로 한 기간은 시험을 더 늦춰도 그대로다.
        try run(ExamPlanMake(course: Self.course, exam: exam, end: Self.day(12, 12)), at: Self.at(12, 8, 15))
        try run(ExamSet(course: Self.course, exam: exam, start: .set(Self.at(12, 21, 9))), at: Self.at(12, 8, 16))
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8, 17))
        #expect(try planned().planPeriod == ExamPlanPeriod(start: Self.day(12, 8), end: Self.day(12, 12)))
    }

    @Test func itemsMoveOnlyToDaysFromTodayToTheExamEve() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let solve = try item(.note(hall, .solve))
        func move(to day: LocalDate, at now: Date) throws {
            try run(ExamPlanMove(course: Self.course, exam: exam, items: [solve.id], day: day), at: now)
        }
        try move(to: Self.day(12, 13), at: Self.at(12, 9))
        #expect(try item(.note(hall, .solve)).day == Self.day(12, 13))
        // 시험 날과 그 뒤, 지난 날로는 옮기지 못하고 항목은 제자리에 있다.
        #expect(throws: ActionError.self) { try move(to: Self.day(12, 14), at: Self.at(12, 9)) }
        #expect(throws: ActionError.self) { try move(to: Self.day(12, 20), at: Self.at(12, 9)) }
        #expect(throws: ActionError.self) { try move(to: Self.day(12, 8), at: Self.at(12, 9)) }
        #expect(try item(.note(hall, .solve)).day == Self.day(12, 13))
        // 새벽 3:59는 아직 12/9의 공부일이라 12/9로 옮길 수 있고, 4:00부터는 12/9가 지난 날이다.
        try move(to: Self.day(12, 9), at: Self.at(12, 10, 3, 59))
        #expect(try item(.note(hall, .solve)).day == Self.day(12, 9))
        #expect(throws: ActionError.self) { try move(to: Self.day(12, 9), at: Self.at(12, 10, 4, 0)) }
    }

    @Test func postponingAndAdvancingMoveOnlyTheGivenItems() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let before = try planned().plan
        let proof = try item(.note(hall, .proof)), solve = try item(.note(hall, .solve))
        try run(ExamPlanPostpone(course: Self.course, exam: exam, items: [proof.id, solve.id]), at: Self.at(12, 8, 22))
        var after = try planned().plan
        for old in before where old.id != proof.id && old.id != solve.id { #expect(after.contains(old)) }
        #expect(try item(.note(hall, .proof)).day == Self.day(12, 9) && item(.note(hall, .proof)).postponedFrom == Self.day(12, 8))
        #expect(try item(.note(hall, .solve)).isEdited)

        // 12/11의 정독을 12/9로 앞당긴다. 새벽 3시는 아직 12/9의 공부일이다.
        let read = try item(.note(brooks, .read))
        try run(ExamPlanAdvance(course: Self.course, exam: exam, items: [read.id]), at: Self.at(12, 10, 3))
        after = try planned().plan
        #expect(after.first { $0.id == read.id }?.day == Self.day(12, 9))
        #expect(try item(.note(brooks, .solve)).day == Self.day(12, 11))
        // 오늘이나 지난 날의 항목은 앞당길 것이 없다.
        #expect(throws: ActionError.self) {
            try run(ExamPlanAdvance(course: Self.course, exam: exam, items: [read.id]), at: Self.at(12, 10, 3))
        }

        // 시험 전날의 항목은 더 미룰 수 없다.
        try run(ExamPlanMove(course: Self.course, exam: exam, items: [solve.id], day: Self.day(12, 13)), at: Self.at(12, 9))
        #expect(try item(.note(hall, .solve)).postponedFrom == nil)
        #expect(throws: ActionError.self) {
            try run(ExamPlanPostpone(course: Self.course, exam: exam, items: [solve.id]), at: Self.at(12, 9))
        }
        #expect(throws: ActionError.self) {
            try run(ExamPlanPostpone(course: Self.course, exam: exam, items: [UUID()]), at: Self.at(12, 9))
        }
    }

    @Test func checkingSeveralStagesLogsEachAndKeepsThemThroughAReplan() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let read = try item(.note(hall, .read)), proof = try item(.note(hall, .proof))
        try run(ExamPlanCheck(course: Self.course, items: [read.id, proof.id]), at: Self.at(12, 8, 20))
        let log = try ActionContext(gist: gist, device: device).store(Self.course).log.readAll().events(PlanCheckEvent.self)
        #expect(Set(log.map(\.event.itemId)) == [read.id, proof.id])
        #expect(throws: ActionError.self) { try run(ExamPlanCheck(course: Self.course, items: [read.id, UUID()]), at: Self.at(12, 8, 21)) }

        // 기간을 바꿔 다시 놓아도 끝낸 단계는 그날에 남고 남은 문제풀이만 새 기간으로 간다.
        try run(ExamPlanMake(course: Self.course, exam: exam, start: Self.day(12, 10), end: Self.day(12, 12)), at: Self.at(12, 9))
        #expect(try item(.note(hall, .read)) == read && item(.note(hall, .proof)) == proof)
        #expect(try item(.note(hall, .solve)).day == Self.day(12, 10))
    }

    @Test func removedItemsStayOutAndWrittenTasksAreDeleted() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let mine = UUID()
        try run(ExamPlanAdd(id: mine, course: Self.course, exam: exam, title: "교재 3장", day: Self.day(12, 9)), at: Self.at(12, 8))
        let solve = try item(.note(brooks, .solve))
        try run(ExamPlanRemove(course: Self.course, exam: exam, items: [solve.id, mine]), at: Self.at(12, 8))
        var plan = try planned().plan
        #expect(!plan.contains { $0.id == mine } && plan.first { $0.id == solve.id }?.isRemoved == true)
        // 뺀 항목은 다시 가리킬 수 없고, 다시 놓아도 돌아오지 않는다.
        #expect(throws: ActionError.self) {
            try run(ExamPlanRemove(course: Self.course, exam: exam, items: [solve.id]), at: Self.at(12, 8))
        }
        try run(ExamPlanMake(course: Self.course, exam: exam, end: Self.day(12, 12)), at: Self.at(12, 8))
        plan = try planned().plan
        #expect(plan.count { $0.target == .note(brooks, .solve) && !$0.isRemoved } == 0)
        #expect(try file().name(of: solve.id) == "기말 02 채색수 문제풀이")
    }

    @Test func aNoteForAUnitReplacesItsMakeNoteItemAndARemovedNoteTakesItsItems() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        let planarNote = UUID()
        try run(NoteAdd(id: planarNote, course: Self.course, title: "기말 03 평면 그래프", kind: .unit, units: [planar]), at: Self.at(12, 8, 13))
        #expect(try needsPlan(on: Self.at(12, 8, 14)))
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8, 14))
        var plan = try planned().plan
        #expect(!plan.contains { $0.target.kind == .makeNote })
        #expect(plan.filter { $0.target.id == planarNote }.map(\.target.stage) == [.read, .solve])

        try run(NoteRemove(course: Self.course, note: "Notes/기말 03 평면 그래프.md"), at: Self.at(12, 8, 15))
        plan = try planned().plan
        #expect(!plan.contains { $0.target.id == planarNote })
        #expect(try needsPlan(on: Self.at(12, 8, 15)))
    }

    @Test func removingAUnitDropsItsMakeNoteItem() throws {
        try run(ExamPlanMake(course: Self.course, exam: exam), at: Self.at(12, 8))
        try run(UnitRemove(course: Self.course, unit: planar), at: Self.at(12, 8, 13))
        #expect(try !planned().plan.contains { $0.target.kind == .makeNote })
    }
}
