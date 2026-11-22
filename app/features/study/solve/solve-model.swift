import FolioAI
import FolioActions
import FolioCore
import FolioDomain
import Foundation
import Observation

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
    var answers: [UUID: String] = [:]
    // 손필기 답은 PNG로 둔다. Claude에 보낼 때 형식을 하나로 맞추기 위해서다.
    var images: [Data] = []
    private var savedImages: [UUID: [Data]] = [:]
    var graded: Graded?
    var grading = false
    var failure: String?
    private(set) var outcomes: [Outcome] = []
    private(set) var started: Date?
    // 모의시험을 멈춘 시각과 지금까지 멈춰 있던 시간이다. 멈춘 동안은 남은 시간이 줄지 않는다.
    private(set) var pausedAt: Date?
    private var pausedFor: TimeInterval = 0
    // 이 과목에서 풀다 둔 차례다. 고르기 화면이 이어 풀기를 권한다.
    private(set) var resumable: SolveResume?

    init(workspace: Workspace, request: SolveRequest) {
        self.workspace = workspace
        self.request = request
        mode = request.mode ?? .typing
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

    var setupNote: String { String(localized: .solvePickedCount(picked.count)) }

    var startTitle: String { String(localized: isMock ? .solveStartMock : .solveStart) }

    func start() {
        queue = picked.map(\.problem.id)
        guard !queue.isEmpty else { return }
        begin()
    }

    private func begin() {
        index = 0
        phase = .solving
        started = workspace.now
        load()
    }

    // MARK: Solving

    var current: CourseStudy.ProblemRecord? {
        guard queue.indices.contains(index) else { return nil }
        return study?.problems[queue[index]]
    }

    var hidesUnits: Bool { isMock || pick.order == .shuffled }

    var mockMinutes: Int {
        request.minutes ?? study?.mockMinutes(for: study?.nextExam(now: workspace.now, calendar: workspace.calendar)) ?? 1
    }

    var mockDeadline: Date? {
        guard isMock, let started else { return nil }
        return started.addingTimeInterval(TimeInterval(mockMinutes * 60) + pausedFor)
    }

    var isPaused: Bool { pausedAt != nil }

    // 멈춘 동안에는 시계를 세우고 시간이 끝나도 내지 않는다.
    var runningDeadline: Date? { isPaused ? nil : mockDeadline }

    func remaining(at now: Date) -> TimeInterval {
        guard let deadline = mockDeadline else { return 0 }
        return max(deadline.timeIntervalSince(pausedAt ?? now), 0)
    }

    func togglePause() {
        guard isMock, phase == .solving else { return }
        if let pausedAt {
            pausedFor += workspace.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        } else {
            pausedAt = workspace.now
        }
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
        return (units + [mode.label, String(localized: .solveProgress(index + 1, queue.count))]).joined(separator: " · ")
    }

    var steps: [Verdict?] {
        queue.enumerated().map { i, id in
            if isMock { return nil }
            if i == index { return graded?.verdict }
            return outcomes.first { $0.id == id }?.graded.verdict
        }
    }

    var canGrade: Bool { !grading && graded == nil && (!images.isEmpty || !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var handwriting: Bool { mode == .handwriting || (isMock && current?.problem.format == .written) }

    func attach(_ urls: [URL]) { images += urls.flatMap(AnswerImages.png(from:)) }

    // 서술과 손필기 답은 넓은 칸이 필요해 문제 옆 칸에 둔다.
    var answersBeside: Bool { handwriting || current?.problem.format == .written }

    func options(of problem: Problem) -> [String] { problem.format == .trueFalse ? Problem.trueFalseOptions : problem.options }

    // 채점한 뒤에는 맞는 답과 고른 답을 색으로 보인다.
    func tone(of option: String, in problem: Problem) -> Tone? {
        guard let graded, !isMock else { return nil }
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

    // 모의시험 중에는 해설을 숨긴다. 시험장에서 볼 수 없기 때문이다.
    var solutionPage: PageLink? {
        guard !(isMock && phase == .solving), let r = current, let set = set(of: r), let material = set.solutionMaterialId,
            r.problem.solutionPage != nil
        else { return nil }
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
        answer = current.flatMap { answers[$0.problem.id] } ?? ""
        why = ""
        images = current.flatMap { savedImages[$0.problem.id] } ?? []
        graded = nil
        failure = nil
    }

    func choose(_ option: String) {
        answer = option
        if current?.problem.format == .trueFalse, !isMock { grade() }
    }

    func grade() {
        guard let record = current, let course else { return }
        let problem = record.problem, text = answer, pictures = images
        if pictures.isEmpty, let verdict = problem.keyVerdict(for: text) {
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
                let outcome = try await client.grade(problem, answer: text, answerImages: pictures)
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
        guard let graded, graded.verdict == .correct, !isMock, let status = current?.status else { return false }
        return WrongFlow.staysRecheck(status, rightOn: workspace.today)
    }

    var asksWhy: Bool { !isMock && graded != nil && current?.problem.format == .trueFalse }

    // 한 키(`solveGo`)로 채점하고 넘긴다. 채점할 것이 없으면 아무것도 하지 않는다.
    func go() {
        if isMock {
            if isLast { submitMock() } else { next() }
        } else if graded == nil {
            if canGrade { grade() }
        } else {
            next()
        }
    }

    var reasons: [WrongReason] { WrongReason.choices(mock: isMock) }

    var isLast: Bool { index >= queue.count - 1 }

    // 채점을 마친 문제만 로그에 쓴다. 건너뛴 문제는 기록이 없어 안 푼 문제로 남는다.
    func next() {
        if let record = current, let g = graded {
            log(record, g)
        } else if isMock {
            keep()
        }
        if isLast {
            finish()
        } else {
            index += 1
            load()
        }
    }

    func back() {
        guard index > 0 else { return }
        if isMock { keep() }
        index -= 1
        load()
    }

    private func keep() {
        guard let id = current?.problem.id else { return }
        answers[id] = answer
        savedImages[id] = images
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

    // 모의시험은 내고 나서 한 번에 채점한다. 답이 없는 문제는 틀림이다.
    func submitMock() {
        keep()
        guard let course, let study else { return }
        let records = queue.compactMap { study.problems[$0] }
        let answers = answers, pictures = savedImages, ready = claudeReady
        let client = workspace.claude(for: course)
        grading = true
        Task {
            for record in records {
                let text = answers[record.problem.id] ?? "", drawn = pictures[record.problem.id] ?? []
                let blank = text.isEmpty && drawn.isEmpty
                var g = Graded(verdict: .wrong, basis: .user, reason: blank ? .time : nil, feedback: [], answer: text)
                if !blank {
                    if drawn.isEmpty, let v = record.problem.keyVerdict(for: text) {
                        g = Graded(verdict: v, basis: .key, reason: nil, feedback: [], answer: text)
                    } else if ready, let outcome = try? await client.grade(record.problem, answer: text, answerImages: drawn) {
                        g = Graded(
                            verdict: outcome.grade.verdict, basis: outcome.basis, reason: outcome.grade.reason,
                            feedback: outcome.grade.feedback, answer: text)
                    }
                }
                self.log(record, g)
            }
            grading = false
            finish()
        }
    }

    private func finish() {
        if let item = request.planItem { workspace.setPlanItem(item, done: true, course: request.course) }
        SolveResume.clear(for: request.course)
        phase = .done
    }

    // MARK: Resume

    // 풀기 화면을 떠날 때 부른다. 모의시험은 시간을 재므로 남기지 않는다. 채점까지 한 문제는 이미 로그에 있으므로, 채점하지 않은 문제부터 다시 연다.
    // 이어 풀기는 과목 전체의 풀기에서만 묻으므로(`init`), 문제를 정해 연 풀기(계획 항목, 문제 묶음)는 남기지 않는다. 남기면 과목 전체의 풀기가
    // 계획의 차례를 권하고, 끝까지 풀어도 그 계획 항목은 체크되지 않는다.
    func leave() {
        guard phase == .solving, !isMock, !queue.isEmpty, request.problems.isEmpty, request.planItem == nil else { return }
        let from = graded == nil ? index : index + 1
        if let record = current, let g = graded { log(record, g) }
        guard from < queue.count else { return SolveResume.clear(for: request.course) }
        SolveResume.remember(
            SolveResume(queue: queue, index: from, mode: mode, order: pick.order, runId: runId),
            for: request.course)
    }

    var resumeLine: String? {
        resumable.map { String(localized: .solveResumeLine($0.index + 1, $0.queue.count)) }
    }

    func resume() {
        guard let saved = resumable else { return }
        queue = saved.queue
        mode = saved.mode
        pick.order = saved.order
        runId = saved.runId
        resumable = nil
        phase = .solving
        started = workspace.now
        index = saved.index
        load()
    }

    func dropResume() {
        SolveResume.clear(for: request.course)
        resumable = nil
    }

    // MARK: Result

    var resultLine: String {
        let right = outcomes.filter { $0.graded.verdict == .correct }.count
        let points = outcomes.compactMap { o in o.record.problem.points.map { (o.graded.verdict.score * $0, $0) } }
        let score = points.isEmpty ? nil : (points.map(\.0).reduce(0, +), points.map(\.1).reduce(0, +))
        let base = String(localized: .solveResultRight(right, outcomes.count))
        return score.map { base + " · " + String(localized: .solveResultPoints(Int($0.0.rounded()), Int($0.1.rounded()))) } ?? base
    }

    var reasonSummary: [(reason: WrongReason, count: Int)] {
        let reasons = outcomes.compactMap(\.graded.reason)
        return WrongReason.allCases.filter(reasons.contains).map { r in (r, reasons.filter { $0 == r }.count) }
    }

    var wrongCount: Int { outcomes.filter { $0.graded.verdict.isMistake }.count }

    // 틀린 문제만 같은 방법으로 다시 푼다. 모의시험은 다시 풀 때 시간을 재지 않는다.
    func retryWrong() {
        let wrong = outcomes.filter { $0.graded.verdict.isMistake }.map(\.id)
        guard !wrong.isEmpty else { return }
        if isMock { mode = .typing }
        outcomes = []
        answers = [:]
        savedImages = [:]
        queue = wrong
        begin()
    }

    struct UnitResult: Identifiable {
        var unit: FolioDomain.Unit
        var line: String
        var readiness: UnitReadiness
        var id: UUID { unit.id }
    }

    func unitResults() -> [UnitResult] {
        guard let study else { return [] }
        let ids = Set(outcomes.flatMap(\.record.problem.unitIds))
        return UnitTree.outline(study.file.units).map(\.unit).filter { ids.contains($0.id) }.map { unit in
            let mine = outcomes.filter { $0.record.problem.unitIds.contains(unit.id) }
            let right = mine.filter { $0.graded.verdict == .correct }.count
            return UnitResult(
                unit: unit, line: String(localized: .solveResultRight(right, mine.count)), readiness: study.readiness(of: unit.id))
        }
    }
}
