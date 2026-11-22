import FolioAI
import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation
import PDFKit

// 필기와 모의시험의 문제집 페이지다(#577). 고른 문제로 문제집 PDF를 만들어 보내고, 손으로 푼 PDF를 받아 한 번에 채점한다.
// 채점한 문제는 바로 로그에 쓰고, 판정을 바꾸면 `ProblemVerdict`로 남긴다. 한 벌을 통째로 내므로 문제마다 내는 단계가 없다.
@MainActor @Observable
final class SolveSheetModel {
    // 문제집의 문제 하나와 그 채점이다. `attempt`는 로그에 쓴 풀이 기록이고, 판정을 바꿀 때 가리킨다.
    struct Row: Identifiable {
        var record: CourseStudy.ProblemRecord
        var title: String
        var graded: SolveModel.Graded?
        var attempt: UUID?
        var page: Int?
        var id: UUID { record.problem.id }
    }

    // 필기로 풀 문제집과 풀이집이다.
    struct Collection: Equatable {
        var url: URL
        var problemsMaterial: UUID?
        var solutionsMaterial: UUID?
    }

    // 같은 이름의 PDF가 Folio가 만든 것이 아니라서 묻는 중인 빌드다. 덮어쓰기를 누르면 이 PDF로 바꾼다.
    private struct HeldCollection {
        var problems: URL
        var solutions: URL
    }

    let workspace: Workspace
    let course: UUID
    let mode: SolveMode
    let problems: [UUID]
    let planItem: UUID?
    let minutes: Int
    private let runId = UUID()
    // 테스트는 가짜 프로바이더를 준다. 테스트 host는 이 Mac의 Claude에 닿지 않는다(`Workspace.claudeReady`).
    @ObservationIgnored var claudeStandIn: ClaudeClient?

    private(set) var collection: Collection?
    private(set) var buildingCollection = false
    private(set) var collectionFailure: String?
    private var heldCollection: HeldCollection?
    // Claude에게 그림과 풀이를 맡긴 항목 수와 끝낸 수다. 맡기는 동안만 있다.
    private(set) var drawing: (done: Int, total: Int)?
    // 다시 그리지 못해 자른 그림을 넣은 항목 수다.
    private(set) var undrawn = 0

    // 낸 PDF의 사본이다. 파일 고르기로 받은 URL은 그 순간에만 읽을 수 있어서 받자마자 복사해 둔다.
    private(set) var submitted: URL?
    private(set) var submittedName: String?
    private var imported: URL?
    private(set) var grading = false
    private(set) var gradeFailure: String?
    private(set) var rows: [Row] = []

    // 모의시험은 문제집이 생긴 때부터 잰다. 그림을 다시 그리는 데 몇 분이 걸리기 때문이다.
    private(set) var started: Date?
    private(set) var pausedAt: Date?
    private var pausedFor: TimeInterval = 0

    init(workspace: Workspace, course: UUID, mode: SolveMode, problems: [UUID], planItem: UUID?, minutes: Int) {
        self.workspace = workspace
        self.course = course
        self.mode = mode
        self.problems = problems
        self.planItem = planItem
        self.minutes = minutes
        rows = Self.printed(workspace: workspace, course: course, problems: problems)
    }

    var isMock: Bool { mode == .mock }
    var study: CourseStudy? { workspace.study(of: course) }

    // 문제집에 찍힌 차례다. 묶음마다 문제지의 차례이고, Claude도 이 차례로 채점한다.
    private static func printed(workspace: Workspace, course: UUID, problems: [UUID]) -> [Row] {
        guard let loaded = workspace.course(course), let study = workspace.study(of: course) else { return [] }
        let sections = ProblemCollection.sections(sets: loaded.file.problemSets, picked: Set(problems))
        return sections.flatMap { section in
            section.items.compactMap { item -> Row? in
                guard case .problem(let p) = item, let record = study.problems[p.id] else { return nil }
                let set = loaded.file.problemSets.first { $0.id == record.setId }
                let path = set.map { ProblemTree($0).path(to: p.id) } ?? []
                let number = path.isEmpty ? p.number : path.joined(separator: " › ")
                return Row(record: record, title: String(localized: .problemsNumbered(section.title, number)))
            }
        }
    }

    var subtitle: String {
        let parts = [mode.label, String(localized: .problemsCount(rows.count))]
        return (isMock ? parts + [String(localized: .solveSheetUnitsHidden)] : parts).joined(separator: " · ")
    }

    // MARK: Collection

    var collectionTitle: String {
        if let drawing { return String(localized: .solveCollectionDrawing(drawing.done, drawing.total)) }
        if buildingCollection { return String(localized: .solveCollectionBuilding) }
        return String(localized: collection == nil ? .solveCollectionBuild : .solveCollectionRebuild)
    }

    var collectionDetail: String {
        if let collectionFailure { return collectionFailure }
        if heldCollection != nil { return String(localized: .solveCollectionReplaceDetail) }
        if undrawn > 0, collection != nil { return String(localized: .solveCollectionUndrawn(undrawn)) }
        if let collection { return collection.url.lastPathComponent }
        return String(localized: .solveCollectionDetail)
    }

    var asksToReplaceCollection: Bool { heldCollection != nil }

    // Claude가 있으면 먼저 그림을 다시 그리고 빠진 풀이를 쓴다. Tectonic 컴파일은 몇 초가 걸려서 화면 밖에서 하고, 만든 PDF를
    // 액션에 넘긴다.
    func buildCollection() async {
        guard !buildingCollection, let loaded = workspace.course(course), !problems.isEmpty else { return }
        buildingCollection = true
        collectionFailure = nil
        heldCollection = nil
        undrawn = 0
        defer { buildingCollection = false }

        if let client {
            let jobs = ProblemArtDrawing.jobs(loaded, picked: problems)
            if !jobs.isEmpty {
                drawing = (0, jobs.count)
                let outcome = await ProblemArtDrawing(workspace: workspace, course: course, client: client).run(jobs) {
                    [weak self] done in self?.drawing?.done = done
                }
                drawing = nil
                undrawn = outcome.failed
            }
        }

        guard let loaded = workspace.course(course) else { return }
        let files = ProblemCollectionFiles(
            store: loaded.store, file: loaded.file,
            semester: workspace.transcript.semesters.first { $0.id == loaded.file.course.semesterId },
            author: workspace.settings.study.coverName, problems: problems, art: await Self.art(loaded, picked: problems))
        let (now, calendar) = (workspace.now, workspace.calendar)
        do {
            let built = try await Task.detached { try files.build(at: now, calendar: calendar) }.value
            place(built.problems, built.solutions, overwrite: false)
        } catch {
            collectionFailure = "\(error)"
        }
    }

    private var client: ClaudeClient? {
        if let claudeStandIn { return claudeStandIn }
        guard workspace.claudeReady, let loaded = workspace.course(course) else { return nil }
        return workspace.claude(for: loaded)
    }

    // 고른 문제와 그 지문의 다시 그린 그림을 PDF로 그린다. 그리지 못한 그림은 빼서 자른 그림이 들어가게 한다.
    private static func art(_ course: LoadedCourse, picked: [UUID]) async -> [UUID: ProblemCollectionFiles.Art] {
        let wanted = Set(picked + course.file.problemSets.flatMap { s in picked.flatMap { ProblemTree(s).stems(of: $0).map(\.id) } })
        var art: [UUID: ProblemCollectionFiles.Art] = [:]
        for (id, doc) in course.store.problemArt() where wanted.contains(id) {
            func pdf(_ svg: String?) async -> Data? {
                guard let svg else { return nil }
                return try? await FigurePDF.render(svg)
            }
            let a = ProblemCollectionFiles.Art(figure: await pdf(doc.model.figure), solution: await pdf(doc.model.solutionFigure))
            if a.figure != nil || a.solution != nil { art[id] = a }
        }
        return art
    }

    func replaceCollection() {
        guard let held = heldCollection else { return }
        heldCollection = nil
        place(held.problems, held.solutions, overwrite: true)
    }

    private func place(_ pdf: URL, _ solutions: URL, overwrite: Bool) {
        do {
            _ = try workspace.runThrowing(
                ProblemCollectionBuild(
                    course: course, problems: problems, pdf: pdf.path, solutionsPDF: solutions.path, overwrite: overwrite))
        } catch ActionError.conflict {
            heldCollection = HeldCollection(problems: pdf, solutions: solutions)
            return
        } catch {
            collectionFailure = "\(error)"
            return
        }
        guard let loaded = workspace.course(course) else { return }
        let files = ProblemCollectionFiles(store: loaded.store, file: loaded.file, semester: nil, author: "", problems: problems)
        let material = { (path: String) in loaded.file.materials.first { $0.path == path }?.id }
        collection = Collection(
            url: loaded.store.fileURL(files.problemsPath), problemsMaterial: material(files.problemsPath),
            solutionsMaterial: material(files.solutionsPath))
        if isMock, started == nil { started = workspace.now }
    }

    func openCollection(solutions: Bool, _ openLink: OpenLinkAction) {
        guard let id = solutions ? collection?.solutionsMaterial : collection?.problemsMaterial else { return }
        openLink(AppLink(.material, id), in: .beside, course: course)
    }

    // MARK: Timer

    var deadline: Date? { started.map { $0.addingTimeInterval(TimeInterval(minutes * 60) + pausedFor) } }

    var isPaused: Bool { pausedAt != nil }

    // 멈춘 동안에는 시계를 세운다. 채점한 뒤에는 시간을 재지 않는다.
    var runningDeadline: Date? { isPaused || isGraded ? nil : deadline }

    func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return TimeInterval(minutes * 60) }
        return max(deadline.timeIntervalSince(pausedAt ?? now), 0)
    }

    func elapsedFraction(at now: Date) -> Double {
        let total = TimeInterval(minutes * 60)
        return total > 0 ? 1 - remaining(at: now) / total : 0
    }

    func timeIsUp(at now: Date) -> Bool { started != nil && remaining(at: now) <= 0 }

    func togglePause() {
        guard isMock, started != nil, !isGraded else { return }
        if let pausedAt {
            pausedFor += workspace.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        } else {
            pausedAt = workspace.now
        }
    }

    // MARK: Submission

    func submit(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
        do { submitted = try ReceivedFile.copy(url) } catch {
            gradeFailure = "\(error)"
            return
        }
        submittedName = url.lastPathComponent
        gradeFailure = nil
    }

    var submittedLine: String? {
        guard let submitted, let submittedName else { return nil }
        let pages = PDFDocument(url: submitted)?.pageCount
        return [submittedName, pages.map { String(localized: .solveSheetPages($0)) }].compactMap { $0 }.joined(separator: " · ")
    }

    var isGraded: Bool { rows.contains { $0.graded != nil } }

    var ungraded: [Row] { rows.filter { $0.graded == nil } }

    var canGrade: Bool { submitted != nil && collection != nil && !grading && !ungraded.isEmpty && client != nil }

    var gradeTitle: String {
        if grading { return String(localized: .solveSheetGrading) }
        if isGraded { return String(localized: .solveSheetGradeRest(ungraded.count)) }
        return String(localized: .solveSubmit)
    }

    var gradeDetail: String? {
        if let gradeFailure { return gradeFailure }
        if client == nil { return String(localized: .solveSheetNeedsClaude) }
        if isGraded, !ungraded.isEmpty { return String(localized: .solveSheetUngraded(ungraded.count)) }
        return nil
    }

    // 채점하지 못한 문제만 다시 맡긴다. 채점한 문제를 다시 채점하면 같은 풀이가 기록에 두 번 남는다.
    func grade() async {
        guard canGrade, let submitted, let client, let loaded = workspace.course(course) else { return }
        grading = true
        gradeFailure = nil
        defer { grading = false }
        let pdf: Data
        do { pdf = try Data(contentsOf: submitted) } catch {
            gradeFailure = "\(error)"
            return
        }
        let asked = ungraded.map { row in
            CollectionProblem(
                set: loaded.file.problemSets.first { $0.id == row.record.setId }?.title ?? "", problem: row.record.problem,
                stems: loaded.file.problemSets.first { $0.id == row.record.setId }.map { ProblemTree($0).stems(of: row.id) } ?? [])
        }
        let grades: [CollectionGrade]
        do { grades = try await client.gradeCollection(asked, submitted: pdf, mock: isMock) } catch {
            gradeFailure = String(localized: .solveGradeFailed("\(error)"))
            return
        }
        keep(submitted, in: loaded)
        for g in grades {
            guard let i = rows.firstIndex(where: { $0.id == g.problem }) else { continue }
            let graded = SolveModel.Graded(
                verdict: g.outcome.grade.verdict, basis: g.outcome.basis, reason: g.outcome.grade.reason,
                feedback: g.outcome.grade.feedback, answer: "")
            let attempt = UUID()
            workspace.run(
                ProblemSolve(
                    id: attempt, course: course, set: rows[i].record.setId, problem: g.problem, verdict: graded.verdict,
                    basis: graded.basis, mode: mode, reason: graded.reason, feedback: graded.feedback, run: runId))
            rows[i].graded = graded
            rows[i].attempt = attempt
            rows[i].page = g.page
        }
        if ungraded.isEmpty {
            if let planItem { workspace.setPlanItem(planItem, done: true, course: course) }
        } else {
            gradeFailure = String(localized: .solveSheetUngraded(ungraded.count))
        }
    }

    // 낸 PDF는 Study에 남긴다(#577). 다시 채점할 때는 이미 들여온 PDF를 또 들여오지 않는다.
    private func keep(_ submitted: URL, in loaded: LoadedCourse) {
        guard imported != submitted else { return }
        let files = ProblemCollectionFiles(store: loaded.store, file: loaded.file, semester: nil, author: "", problems: [])
        try? ReceivedFile.renamed(submitted, to: files.answersFileName) { copy in
            workspace.importFiles([copy], into: CourseFolder.study.rawValue, course: course)
            imported = submitted
        }
    }

    // MARK: Verdicts

    // 판정을 바꾸면 바꾼 것이 최종이다. 맞음으로 바꾸면 틀린 이유를 지운다.
    func override(_ id: UUID, _ verdict: Verdict) {
        guard let i = rows.firstIndex(where: { $0.id == id }), var g = rows[i].graded, g.verdict != verdict else { return }
        g.verdict = verdict
        g.basis = .user
        if !verdict.isMistake { g.reason = nil }
        record(i, g)
    }

    func setReason(_ id: UUID, _ reason: WrongReason) {
        guard let i = rows.firstIndex(where: { $0.id == id }), var g = rows[i].graded, g.verdict.isMistake else { return }
        g.reason = reason
        record(i, g)
    }

    private func record(_ i: Int, _ g: SolveModel.Graded) {
        guard let attempt = rows[i].attempt else { return }
        workspace.run(ProblemVerdict(course: course, attempt: attempt.uuidString, verdict: g.verdict, reason: g.reason))
        rows[i].graded = g
    }

    var reasons: [WrongReason] { WrongReason.choices(mock: isMock) }

    // 채점한 행의 둘째 줄이다. 단원, 채점 근거, 풀이를 찾은 쪽이다. 채점 전에는 단원만 보이고, 모의시험은 채점 전에 단원을 가린다.
    func detail(_ row: Row) -> String {
        let units =
            isMock && !isGraded ? [] : row.record.problem.unitIds.compactMap { id in study?.file.units.first { $0.id == id }?.title }
        guard let graded = row.graded else { return units.joined(separator: " · ") }
        let basis = String(localized: .solveBasis(graded.basis.label))
        return (units + [basis] + [row.page.map { String(localized: .solveSheetPages($0)) }].compactMap { $0 }).joined(separator: " · ")
    }

    var gradedNote: String { String(localized: .solveSheetGradedNote(outcomes.count, rows.count)) }

    // MARK: Result

    var outcomes: [SolveModel.Outcome] { rows.compactMap { r in r.graded.map { SolveModel.Outcome(record: r.record, graded: $0) } } }

    var resultLine: String { SolveModel.resultLine(outcomes) }

    var reasonSummary: [(reason: WrongReason, count: Int)] { SolveModel.reasonSummary(outcomes) }

    func unitResults() -> [SolveModel.UnitResult] { study.map { SolveModel.unitResults(outcomes, study: $0) } ?? [] }
}
