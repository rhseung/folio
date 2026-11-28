import FolioAI
import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation

// 풀기 화면이다. 화면에서는 참·거짓, 객관식, 단답을 한 문제씩 풀어 바로 채점하고(개념 확인), 필기와 모의시험은 문제집
// PDF를 손으로 풀어 한 번에 낸다(`SolveSheetModel`, #577).
@MainActor @Observable
final class SolveModel {
    enum Phase { case setup, solving, done }

    // 채점이 끝난 한 문제다. 로그에 쓰기 전까지 판정과 이유를 바꿀 수 있다.
    struct Graded: Equatable {
        var verdict: Verdict
        var basis: GradeBasis
        var reason: WrongReason?
        var feedback: [String]
        var answer: String
    }

    // 문제지, 해설, 렉처의 쪽이다. 풀기 화면 옆 칸에 그 자료를 연다.
    struct PageLink: Hashable {
        var material: UUID
        var page: Int?

        // 문제의 쪽과 링크의 쪽은 모두 1부터 센다.
        var link: AppLink { AppLink(.material, material, anchor: page.map(AppLink.Anchor.page)) }
    }

    struct Outcome: Identifiable {
        var record: CourseStudy.ProblemRecord
        var graded: Graded
        var id: UUID { record.problem.id }
    }

    let workspace: Workspace
    let request: SolveRequest
    var phase: Phase
    var mode: SolveMode
    var pick: SolvePick
    var count = 0
    private let seed = UInt64.random(in: 1...UInt64.max)
    private var runId = UUID()
    private(set) var queue: [UUID] = []
    var index = 0
    var answer = ""
    // 참거짓에 붙이는 이유 한 줄이다.
    var why = ""
    var graded: Graded?
    var grading = false
    var failure: String?
    private(set) var outcomes: [Outcome] = []
    // 필기와 모의시험의 문제집 페이지다. 시작한 뒤에만 있다.
    private(set) var sheet: SolveSheetModel?
    // 이 과목에서 풀다 둔 차례다. 고르기 화면이 이어 풀기를 권한다.
    private(set) var resumable: SolveResume?

    init(workspace: Workspace, request: SolveRequest) {
        self.workspace = workspace
        self.request = request
        let formats = request.problems.compactMap { workspace.study(of: request.course)?.problems[$0]?.problem.format }
        mode = SolveMode.fitting(request.mode, formats: formats)
        pick = SolvePick(units: Set(request.units), sets: request.set.map { [$0] } ?? [], order: request.shuffled ? .shuffled : .byUnit)
        phase = .setup
        if request.problems.isEmpty, request.planItem == nil { resumable = SolveResume.saved(for: request.course, in: workspace) }
        if !request.problems.isEmpty {
            queue = request.problems
            begin()
        }
    }

    var study: CourseStudy? { workspace.study(of: request.course) }
    var course: LoadedCourse? { workspace.course(request.course) }
    var claudeReady: Bool { workspace.claudeReady }
    var isMock: Bool { mode == .mock }
    var accent: CourseAccent { workspace.accent(request.course) }

    // MARK: Setup

    var picked: [CourseStudy.ProblemRecord] {
        guard let study else { return [] }
        var p = pick
        p.count = count == .zero ? nil : count
        p.onScreenOnly = !mode.onPaper
        return p.pick(from: study, seed: seed)
    }

    var unitOptions: [SelectOption<UUID?>] {
        let units = UnitTree.outline(study?.file.units ?? [])
        return [SelectOption(id: UUID?.none, label: String(localized: .solveAllUnits))]
            + units.map { SelectOption(id: Optional($0.unit.id), label: $0.unit.title, depth: $0.depth) }
    }

    var unit: UUID? {
        get { pick.units.first }
        set { pick.units = newValue.map { [$0] } ?? [] }
    }

    var sourceOptions: [(ProblemSource?, String)] {
        [(nil, String(localized: .solveAllSources))] + ProblemSource.allCases.map { (Optional($0), $0.label) }
    }

    var source: ProblemSource? {
        get { pick.sources.first }
        set { pick.sources = newValue.map { [$0] } ?? [] }
    }

    var countOptions: [(Int, String)] {
        [(0, String(localized: .solveCountAll))] + [5, 10, 20].map { ($0, String(localized: .problemsCount($0))) }
    }

    var filterOptions: [(SolvePick.Filter, String)] {
        [
            (.wrong, String(localized: .solveFilterWrong)), (.untried, String(localized: .solveFilterUntried)),
            (.all, String(localized: .solveFilterAll)),
        ]
    }

    var orderOptions: [(SolvePick.Order, String)] {
        [(.byUnit, String(localized: .solveOrderByUnit)), (.shuffled, String(localized: .solveOrderShuffled))]
    }

    var modeOptions: [(SolveMode, String)] { SolveMode.allCases.map { ($0, $0.label) } }

    var modeDetail: String {
        switch mode {
        case .typing: String(localized: .solveModeTypingDetail)
        case .handwriting: String(localized: .solveModeHandwritingDetail)
        case .mock: String(localized: .solveModeMockDetail)
        }
    }

    var setupNote: String { String(localized: .solvePickedCount(picked.count)) }

    var startTitle: String { String(localized: isMock ? .solveStartMock : .solveStart) }

    // 문제집으로 푸는 풀기는 고른 차례가 문제집의 차례가 아니므로(묶음마다 문제지의 차례) 섞기를 묻지 않는다.
    var asksOrder: Bool { !mode.onPaper }

    func start() {
        queue = picked.map(\.problem.id)
        guard !queue.isEmpty else { return }
        begin()
    }

    private func begin() {
        index = 0
        phase = .solving
        if mode.onPaper {
            sheet = SolveSheetModel(
                workspace: workspace, course: request.course, mode: mode, problems: queue, planItem: request.planItem,
                minutes: mockMinutes)
        } else {
            load()
        }
    }

    // MARK: Solving

    var current: CourseStudy.ProblemRecord? {
        guard queue.indices.contains(index) else { return nil }
        return study?.problems[queue[index]]
    }

    var hidesUnits: Bool { pick.order == .shuffled }

    var mockMinutes: Int {
        request.minutes ?? study?.mockMinutes(for: study?.nextExam(now: workspace.now, calendar: workspace.calendar)) ?? 1
    }

    // 소문제의 번호 자리에는 지문의 경로를 쓴다("Warm-up › W1").
    func title(_ r: CourseStudy.ProblemRecord) -> String {
        let set = study?.file.problemSets.first { $0.id == r.setId }
        let path = set.map { ProblemTree($0).path(to: r.problem.id) } ?? []
        return String(localized: .problemsNumbered(set?.title ?? "", path.isEmpty ? r.problem.number : path.joined(separator: " › ")))
    }

    func stems(_ r: CourseStudy.ProblemRecord) -> [ProblemGroup] {
        study?.file.problemSets.first { $0.id == r.setId }.map { ProblemTree($0).stems(of: r.problem.id) } ?? []
    }

    // 그림 칸을 잘라 올 문제지 PDF다.
    func sheet(_ r: CourseStudy.ProblemRecord) -> URL? {
        guard let course = workspace.course(request.course),
            let id = course.file.problemSets.first(where: { $0.id == r.setId })?.materialId,
            let material = course.file.materials.first(where: { $0.id == id && $0.isPDF })
        else { return nil }
        return course.store.fileURL(material.path)
    }

    func subtitle(_ r: CourseStudy.ProblemRecord) -> String {
        let units = hidesUnits ? [] : r.problem.unitIds.compactMap { id in study?.file.units.first { $0.id == id }?.title }
        return (units + [String(localized: .solveProgress(index + 1, queue.count))]).joined(separator: " · ")
    }

    var steps: [Verdict?] {
        queue.enumerated().map { i, id in
            if i == index { return graded?.verdict }
            return outcomes.first { $0.id == id }?.graded.verdict
        }
    }

    var canGrade: Bool { !grading && graded == nil && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func options(of problem: Problem) -> [String] { problem.format == .trueFalse ? Problem.trueFalseOptions : problem.options }

    // 채점한 뒤에는 맞는 답과 고른 답을 색으로 보인다.
    func tone(of option: String, in problem: Problem) -> Tone? {
        guard let graded else { return nil }
        switch problem.mark(of: option, picked: graded.answer, verdict: graded.verdict) {
        case .correct: return .success
        case .wrong: return .danger
        case .partial, nil: return nil
        }
    }

    // MARK: Pages

    private func set(of r: CourseStudy.ProblemRecord) -> ProblemSet? { study?.file.problemSets.first { $0.id == r.setId } }

    var problemPage: PageLink? {
        guard let r = current, let set = set(of: r), let material = set.materialId else { return nil }
        return PageLink(material: material, page: r.problem.page)
    }

    var solutionPage: PageLink? {
        guard let r = current, let set = set(of: r), let material = set.solutionMaterialId, r.problem.solutionPage != nil else {
            return nil
        }
        return PageLink(material: material, page: r.problem.solutionPage)
    }

    var solutionText: String? {
        guard graded != nil, let text = current?.problem.solution, !text.isEmpty else { return nil }
        return text
    }

    var lecturePages: [ProblemPage] {
        guard graded?.reason == .concept || graded?.verdict == .wrong else { return [] }
        return current?.problem.lecturePages ?? []
    }

    // 문제지 쪽은 풀기 화면 옆 칸에 연다. 같은 칸에 열면 풀던 문제를 가리고, 옆 칸은 넓히거나 접을 수 있다.
    func open(_ page: PageLink, _ openLink: OpenLinkAction) { openLink(page.link, in: .beside, course: request.course) }

    func open(_ page: ProblemPage, _ openLink: OpenLinkAction) {
        open(PageLink(material: page.materialId, page: page.page), openLink)
    }

    // 끝내거나 닫으면 풀기를 연 곳으로 돌아간다. 돌아갈 곳이 없으면(주소로 바로 연 풀기) 단원 페이지로 간다.
    func close(_ goBack: GoBackAction, _ openLink: OpenLinkAction) {
        if !goBack() { openLink(.course(request.course, page: .units), course: request.course) }
    }

    private func load() {
        answer = ""
        why = ""
        graded = nil
        failure = nil
    }

    func choose(_ option: String) {
        answer = option
        if current?.problem.format == .trueFalse { grade() }
    }

    func grade() {
        guard let record = current, let course else { return }
        let problem = record.problem, text = answer
        if let verdict = problem.keyVerdict(for: text) {
            graded = Graded(verdict: verdict, basis: .key, reason: nil, feedback: [], answer: text)
            return
        }
        guard claudeReady else {
            graded = Graded(verdict: .wrong, basis: .user, reason: nil, feedback: [], answer: text)
            failure = String(localized: .solveGradeYourself)
            return
        }
        grading = true
        failure = nil
        let client = workspace.claude(for: course)
        Task {
            do {
                let outcome = try await client.grade(problem, answer: text)
                graded = Graded(
                    verdict: outcome.grade.verdict, basis: outcome.basis, reason: outcome.grade.reason, feedback: outcome.grade.feedback,
                    answer: text)
            } catch {
                graded = Graded(verdict: .wrong, basis: .user, reason: nil, feedback: [], answer: text)
                failure = String(localized: .solveGradeFailed("\(error)"))
            }
            grading = false
        }
    }

    func override(_ verdict: Verdict) {
        guard var g = graded, g.verdict != verdict else { return }
        g.verdict = verdict
        g.basis = .user
        if !verdict.isMistake { g.reason = nil }
        graded = g
    }

    func setReason(_ reason: WrongReason) { graded?.reason = reason }

    // 오답을 같은 공부일에 다시 맞혔다. 오답에서 빠지지 않고 "다시 확인"으로 남는다는 것을 알린다.
    var staysRecheck: Bool {
        guard let graded, graded.verdict == .correct, let status = current?.status else { return false }
        return WrongFlow.staysRecheck(status, rightOn: workspace.today)
    }

    var asksWhy: Bool { graded != nil && current?.problem.format == .trueFalse }

    // 한 키(`solveGo`)로 채점하고 넘긴다. 채점할 것이 없으면 아무것도 하지 않는다.
    func go() {
        if graded == nil {
            if canGrade { grade() }
        } else {
            next()
        }
    }

    var reasons: [WrongReason] { WrongReason.choices(mock: false) }

    var isLast: Bool { index >= queue.count - 1 }

    // 채점을 마친 문제만 로그에 쓴다. 건너뛴 문제는 기록이 없어 안 푼 문제로 남는다.
    func next() {
        if let record = current, let g = graded { log(record, g) }
        if isLast {
            finish()
        } else {
            index += 1
            load()
        }
    }

    private func log(_ record: CourseStudy.ProblemRecord, _ g: Graded) {
        workspace.run(
            ProblemSolve(
                id: nil, course: request.course, set: record.setId, problem: record.problem.id, verdict: g.verdict, basis: g.basis,
                mode: mode,
                answer: g.answer.isEmpty ? nil : g.answer, why: record.problem.format == .trueFalse ? why : nil, reason: g.reason,
                feedback: g.feedback, run: runId))
        outcomes.append(Outcome(record: record, graded: g))
    }

    private func finish() {
        if let item = request.planItem { workspace.setPlanItems([item], done: true, course: request.course) }
        SolveResume.clear(for: request.course)
        phase = .done
    }

    // MARK: Resume

    // 풀기 화면을 떠날 때 부른다. 문제집으로 푸는 풀기는 채점한 문제를 바로 로그에 쓰므로 남기지 않는다. 채점까지 한 문제는 이미
    // 로그에 있으므로, 채점하지 않은 문제부터 다시 연다. 이어 풀기는 과목 전체의 풀기에서만 묻으므로(`init`), 문제를 정해 연
    // 풀기(계획 항목, 문제 묶음)는 남기지 않는다. 남기면 과목 전체의 풀기가 계획의 차례를 권하고, 끝까지 풀어도 그 계획 항목은
    // 체크되지 않는다.
    func leave() {
        guard phase == .solving, !mode.onPaper, !queue.isEmpty, request.problems.isEmpty, request.planItem == nil else { return }
        let from = graded == nil ? index : index + 1
        if let record = current, let g = graded { log(record, g) }
        guard from < queue.count else { return SolveResume.clear(for: request.course) }
        SolveResume.remember(SolveResume(queue: queue, index: from, order: pick.order, runId: runId), for: request.course)
    }

    var resumeLine: String? {
        resumable.map { String(localized: .solveResumeLine($0.index + 1, $0.queue.count)) }
    }

    func resume() {
        guard let saved = resumable else { return }
        queue = saved.queue
        mode = .typing
        pick.order = saved.order
        runId = saved.runId
        resumable = nil
        phase = .solving
        index = saved.index
        load()
    }

    func dropResume() {
        SolveResume.clear(for: request.course)
        resumable = nil
    }

    // MARK: Result

    var resultLine: String { Self.resultLine(outcomes) }

    var reasonSummary: [(reason: WrongReason, count: Int)] { Self.reasonSummary(outcomes) }

    var wrongCount: Int { outcomes.filter { $0.graded.verdict.isMistake }.count }

    // 틀린 문제만 다시 푼다.
    func retryWrong() {
        let wrong = outcomes.filter { $0.graded.verdict.isMistake }.map(\.id)
        guard !wrong.isEmpty else { return }
        outcomes = []
        queue = wrong
        begin()
    }

    struct UnitResult: Identifiable {
        var unit: FolioDomain.Unit
        var line: String
        var readiness: UnitReadiness
        var id: UUID { unit.id }
    }

    func unitResults() -> [UnitResult] { study.map { Self.unitResults(outcomes, study: $0) } ?? [] }

    // 화면에서 푼 결과와 문제집의 채점 결과가 같은 모양으로 보이게 함께 쓴다.
    static func resultLine(_ outcomes: [Outcome]) -> String {
        let right = outcomes.filter { $0.graded.verdict == .correct }.count
        let points = outcomes.compactMap { o in o.record.problem.points.map { (o.graded.verdict.score * $0, $0) } }
        let score = points.isEmpty ? nil : (points.map(\.0).reduce(0, +), points.map(\.1).reduce(0, +))
        let base = String(localized: .solveResultRight(right, outcomes.count))
        return score.map { base + " · " + String(localized: .solveResultPoints(Int($0.0.rounded()), Int($0.1.rounded()))) } ?? base
    }

    static func reasonSummary(_ outcomes: [Outcome]) -> [(reason: WrongReason, count: Int)] {
        let reasons = outcomes.compactMap(\.graded.reason)
        return WrongReason.allCases.filter(reasons.contains).map { r in (r, reasons.filter { $0 == r }.count) }
    }

    static func unitResults(_ outcomes: [Outcome], study: CourseStudy) -> [UnitResult] {
        let ids = Set(outcomes.flatMap(\.record.problem.unitIds))
        return UnitTree.outline(study.file.units).map(\.unit).filter { ids.contains($0.id) }.map { unit in
            let mine = outcomes.filter { $0.record.problem.unitIds.contains(unit.id) }
            let right = mine.filter { $0.graded.verdict == .correct }.count
            return UnitResult(
                unit: unit, line: String(localized: .solveResultRight(right, mine.count)), readiness: study.readiness(of: unit.id))
        }
    }
}
