import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class PlanModel {
    // 오늘 화면은 이번 학기 과목의 오늘 줄을, 과목의 공부 탭은 그 과목의 계획을, 시험 화면은 시험 하나의 계획을 보인다.
    enum Scope: Equatable {
        case today
        case course(UUID)
        case exam(course: UUID, exam: UUID)
    }

    struct Period: Identifiable {
        var courseId: UUID
        var exam: Exam
        var title: String
        var period: ExamPlanPeriod
        var start: Date
        var end: Date
        var id: UUID { exam.id }
    }

    let workspace: Workspace
    let scope: Scope
    var pending: PendingAction?
    var showsAll = false
    var newTitle = ""
    var newDay = Date.now
    // 모의고사의 문제 순서를 정하는 씨앗이다. 다시 그려도 같은 순서로 연다.
    private let seed = UInt64.random(in: 1...UInt64.max)

    init(workspace: Workspace, scope: Scope) {
        self.workspace = workspace
        self.scope = scope
        newDay = workspace.today.date(in: workspace.calendar) ?? workspace.now
    }

    var today: LocalDate { workspace.today }

    // MARK: The board

    var board: PlanBoard {
        switch scope {
        case .today: return workspace.planBoard(workspace.currentCourses)
        case .course(let id): return workspace.course(id).map { workspace.planBoard([$0]) } ?? PlanBoard()
        case .exam(let course, let id):
            guard let study = workspace.study(of: course), let exam = study.file.exams.first(where: { $0.id == id }) else {
                return PlanBoard()
            }
            // 어제 오답은 시험이 아니라 과목의 줄이라 시험 하나의 계획에는 두지 않는다.
            var board = study.planBoard([exam])
            board.today.removeAll { $0.examId == nil }
            return board
        }
    }

    var showsCourse: Bool { scope == .today }
    var showsNext: Bool { scope != .today }
    var addsTasks: Bool { if case .exam = scope { true } else { false } }
    // 과목의 공부 탭에서는 블록들이 페이지의 블록 간격으로 선다. 시험 카드 아래와 오늘 화면에서는 한 묶음으로 붙는다.
    var fillsPage: Bool { if case .course = scope { true } else { false } }

    func shows(_ board: PlanBoard, _ periods: [Period]) -> Bool {
        addsTasks || !periods.isEmpty || !board.today.isEmpty || (showsNext && !board.next.isEmpty)
    }

    func todayNote(_ board: PlanBoard) -> String {
        var parts = [dayLabel(today)]
        if board.notes > 0 { parts.append(String(localized: .planNoteNotes(board.notes))) }
        if board.wrong > 0 { parts.append(String(localized: .planNoteWrong(board.wrong))) }
        if board.late > 0 { parts.append(String(localized: .planNoteLate(board.late))) }
        return parts.joined(separator: " · ")
    }

    func nextNote(_ board: PlanBoard) -> String {
        guard let first = board.next.first else { return "" }
        var parts = [String(localized: .planNoteFromDay(dayLabel(first.day)))]
        if board.nextNotes > 0 { parts.append(String(localized: .planNoteLeftNotes(board.nextNotes))) }
        if board.nextMocks > 0 { parts.append(String(localized: .planNoteMocks(board.nextMocks))) }
        return parts.joined(separator: " · ")
    }

    // 접혀 있으면 설정한 날 수의 카드만 낸다.
    func days(_ board: PlanBoard) -> (shown: [PlanBoard.Day], folded: Int) {
        let limit = max(workspace.settings.study.planShownDays, 1)
        let shown = showsAll ? board.next : Array(board.next.prefix(limit))
        return (shown, board.next.count - min(board.next.count, limit))
    }

    func dayLabel(_ day: LocalDate) -> String {
        day.date(in: workspace.calendar).map { CourseFile.day($0, calendar: workspace.calendar) } ?? day.description
    }

    func daySummary(_ day: PlanBoard.Day) -> String {
        let notes = day.rows.count(where: \.kind.isNote)
        let mocks = day.rows.count { $0.kind == .mock }
        return
            ((notes > 0 ? [String(localized: .planNoteNotes(notes))] : []) + (mocks > 0 ? [String(localized: .planNoteMocks(mocks))] : []))
            .joined(separator: " · ")
    }

    // MARK: A row

    func accent(_ row: PlanRow) -> CourseAccent { workspace.accent(row.courseId) }

    func detail(_ row: PlanRow) -> String {
        var parts: [String] = []
        if showsCourse, let course = workspace.course(row.courseId) { parts.append(course.title) }
        if let subject = row.subject { parts.append(String(localized: .planUnit(subject))) }
        if case .course(let id) = scope, plannedExams(in: id).count > 1, let exam = exam(of: row) { parts.append(exam.title) }
        if let from = row.lateFrom { parts.append(String(localized: .planFrom(dayLabel(from)))) }
        return parts.joined(separator: " · ")
    }

    func badge(_ row: PlanRow) -> (text: String, tone: Tone)? {
        switch row.kind {
        case .wrong(let progress): (String(localized: .planNoteWrong(progress.left)), .danger)
        case .makeNote where !row.isDone: (String(localized: .planNoNote), .warning)
        case .makeNote, .note, .mock, .custom: nil
        }
    }

    // 단계가 없는 줄(모의고사, 직접 쓴 할 일, 끝낸 노트 만들기)의 칩에 쓰는 이름이다.
    func label(_ step: PlanRow.Step, in row: PlanRow) -> String {
        if let stage = step.stage { return stage.label }
        return switch row.kind {
        case .mock: String(localized: .planStepMock)
        case .makeNote: String(localized: .planStepMakeNote)
        case .custom, .note, .wrong: String(localized: .menuDone)
        }
    }

    // 하다 만 단계의 칩은 한 양과 전체 양을 이름 뒤에 적는다.
    func chip(_ step: PlanRow.Step, in row: PlanRow) -> String {
        let name = label(step, in: row)
        guard step.progress.isStarted, !step.isDone else { return name }
        return String(localized: .planStepProgress(name, step.progress.done, step.progress.total))
    }

    // 노트 만들기는 경고 꼬리표가 그 자리를 맡으므로, 끝낸 뒤에만 칩을 보인다.
    func steps(_ row: PlanRow) -> [PlanRow.Step] {
        if case .makeNote = row.kind, !row.isDone { return [] }
        return row.steps
    }

    private func study(_ row: PlanRow) -> CourseStudy? { workspace.study(of: row.courseId) }

    private func exam(of row: PlanRow) -> Exam? { workspace.course(row.courseId)?.file.exams.first { $0.id == row.examId } }

    private func plannedExams(in course: UUID) -> [Exam] {
        workspace.study(of: course)?.plannedExams(now: workspace.now, calendar: workspace.calendar) ?? []
    }

    // 줄이나 단계를 누르면 여는 곳이다. 정독은 노트를 열고 그 옆 칸에 노트의 카드를 연다. 모의고사와 어제 오답은 풀기를 열고,
    // 직접 쓴 할 일은 열 곳이 없다.
    enum Destination {
        case link(AppLink, beside: AppLink? = nil)
        case solve(SolveRequest)
    }

    func destination(_ row: PlanRow, stage: PlanStage?) -> Destination? {
        if let link = row.link(for: stage) { return .link(link, beside: row.companion(for: stage)) }
        guard let solve = study(row)?.solve(row, seed: seed) else { return nil }
        return .solve(SolveRequest(plan: solve, course: row.courseId, item: row.open.first))
    }

    // MARK: Changing a row

    func setDone(_ items: [UUID], _ done: Bool, in row: PlanRow) {
        workspace.setPlanItems(items, done: done, course: row.courseId)
    }

    // 직접 쓴 할 일의 칩은 열 곳이 없어 누르면 바로 체크한다.
    func toggle(_ step: PlanRow.Step, in row: PlanRow) { setDone([step.item], !step.isDone, in: row) }

    private func postponing(_ row: PlanRow) -> ExamPlanPostpone? {
        row.examId.map { ExamPlanPostpone(course: row.courseId, exam: $0, items: row.open) }
    }

    func canPostpone(_ row: PlanRow) -> Bool { postponing(row).map(workspace.can) ?? false }

    func postpone(_ row: PlanRow) { if let action = postponing(row) { workspace.run(action) } }

    // 미루면 가는 날이 내일인지에 따라 메뉴의 이름이 달라진다.
    func postponesToTomorrow(_ row: PlanRow) -> Bool { row.day <= today }

    func advance(_ row: PlanRow) {
        guard let exam = row.examId else { return }
        workspace.run(ExamPlanAdvance(course: row.courseId, exam: exam, items: row.open))
    }

    // 날짜 고르기가 내놓는 날이다. 옮길 수 있는 날에서 그 줄이 지금 있는 날을 뺀다.
    func moveDays(_ row: PlanRow) -> [LocalDate] {
        guard let exam = exam(of: row), let study = study(row) else { return [] }
        return study.planDays(of: exam, settings: workspace.settings, calendar: workspace.calendar).prefix(Self.moveDayLimit)
            .filter { $0 != row.day }
    }

    // 메뉴가 화면보다 길어지지 않게 하는 수다. 더 먼 날은 기간을 고쳐서 옮긴다.
    static let moveDayLimit = 21

    func move(_ row: PlanRow, to day: LocalDate) {
        guard let exam = row.examId else { return }
        workspace.run(ExamPlanMove(course: row.courseId, exam: exam, items: row.open, day: day))
    }

    func remove(_ row: PlanRow) {
        guard let exam = row.examId else { return }
        pending = workspace.ask(ExamPlanRemove(course: row.courseId, exam: exam, items: row.steps.map(\.item)))
    }

    // MARK: Periods

    var periods: [Period] {
        let courses: [UUID]
        switch scope {
        case .today: return []
        case .course(let id): courses = [id]
        case .exam(let course, _): courses = [course]
        }
        return courses.flatMap { course in
            plannedExams(in: course).compactMap { exam -> Period? in
                if case .exam(_, let only) = scope, only != exam.id { return nil }
                guard let period = exam.planPeriod, let start = period.start.date(in: workspace.calendar),
                    let end = period.end.date(in: workspace.calendar)
                else { return nil }
                let day = exam.start.map { CourseFile.day($0, calendar: workspace.calendar) } ?? ""
                return Period(
                    courseId: course, exam: exam, title: String(localized: .planPeriodExam(exam.title, day)), period: period, start: start,
                    end: end)
            }
        }
    }

    func periodNote(_ periods: [Period]) -> String {
        guard let first = periods.map(\.period.start).min(), let last = periods.map(\.period.end).max() else { return "" }
        return dayLabel(first) + " – " + dayLabel(last)
    }

    func setStart(_ date: Date, of period: Period) {
        workspace.run(ExamPlanMake(course: period.courseId, exam: period.exam.id, start: LocalDate(date, in: workspace.calendar)))
    }

    func setEnd(_ date: Date, of period: Period) {
        workspace.run(ExamPlanMake(course: period.courseId, exam: period.exam.id, end: LocalDate(date, in: workspace.calendar)))
    }

    func setAfter(_ after: ExamPlanPeriod.After, of period: Period) {
        workspace.run(ExamPlanMake(course: period.courseId, exam: period.exam.id, after: after))
    }

    var afterOptions: [(ExamPlanPeriod.After, String)] {
        [(.empty, String(localized: .planAfterEmpty)), (.mock, String(localized: .planAfterMock))]
    }

    // MARK: Written tasks

    private var adding: ExamPlanAdd? {
        guard case .exam(let course, let exam) = scope else { return nil }
        return ExamPlanAdd(
            course: course, exam: exam, title: newTitle.trimmingCharacters(in: .whitespaces), day: LocalDate(newDay, in: workspace.calendar)
        )
    }

    var canAdd: Bool { adding.map(workspace.can) ?? false }

    func add() {
        guard let adding, workspace.run(adding) != nil else { return }
        newTitle = ""
    }
}
