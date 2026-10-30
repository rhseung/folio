import FolioActions
import FolioAI
import FolioDomain
import Foundation
import Observation

/// One solving round: the scope picked in the left pane, the deck built from it and the answer being graded.
@MainActor @Observable
final class QuizSolveModel {
    let quiz: QuizModel
    var workspace: Workspace { quiz.workspace }

    enum Grading: Hashable { case claude, mine }

    /// A graded answer not yet written to the log. It is written when the user moves on, so a changed verdict
    /// becomes one attempt marked as overridden instead of two.
    struct Pending {
        var cardId: UUID
        var answer: String
        var verdict: Verdict
        let original: Verdict
        let grader: QuizAttemptEvent.Grader
        var missing: [String] = []
        var feedback: String?
        var byClaude = false
    }

    var scope = QuizScope()
    var order: QuizOrder = .unitOrder
    var grading: Grading = .claude
    var label = ""
    var deck: [QuizCard] = []
    var index = 0
    var started = false
    var round: [Verdict] = []
    var answer = ""
    var revealed = false
    var pending: Pending?
    var busy = false
    var failure: String?
    var missingKey = false

    init(quiz: QuizModel) { self.quiz = quiz }

    func units(_ course: LoadedCourse) -> [FolioDomain.Unit] { course.outline.map(\.unit) }

    func prepare(_ course: LoadedCourse) {
        missingKey = !workspace.claudeReady
        if missingKey { grading = .mine }
        if scope.unitIds.isEmpty { scope.unitIds = Set(units(course).map(\.id)) }
    }

    func apply(_ request: SolveRequest, course: LoadedCourse) {
        scope = request.scope
        order = request.order
        start(label: request.label, course: course)
    }

    // MARK: Scope

    struct Pane {
        var byUnit: [UUID: WrongTally]
        var wrong: Int
        var exam: Exam?
        var examCards: Int
        var reviewUnits: Set<UUID>
        var reviewCards: Int
        /// Only units with cards can be picked; the rest are counted and sent to the cards screen.
        var groups: [(title: String?, units: [FolioDomain.Unit])]
        var withCards: Set<UUID>
        var empty: Int
        var preview: Int
    }

    func pane(_ course: LoadedCourse) -> Pane {
        let cards = quiz.cards
        let byUnit = QuizStats.tally(cards, keys: { [$0.unitId] }, history: { self.quiz.history(of: $0.id) })
        let today = workspace.today
        let exam = course.file.exams.filter { ($0.start ?? .distantPast) > workspace.now && !$0.scopeUnitIds.isEmpty }.min { $0.start! < $1.start! }
        let reviewUnits = Set(workspace.reviewQueue(now: workspace.now).filter { $0.courseId == course.id }.map(\.item.unitId))
        let groups = UnitsView.groups(course.outline).compactMap { g -> (title: String?, units: [FolioDomain.Unit])? in
            let rows = ((g.root.map { [$0] } ?? []) + g.rows.map(\.unit)).filter { byUnit[$0.id] != nil }
            return rows.isEmpty ? nil : (g.root?.title, rows)
        }
        let withCards = Set(byUnit.keys)
        return Pane(byUnit: byUnit,
                    wrong: cards.filter { WrongFlow.isDue(quiz.history(of: $0.id), today: today) }.count,
                    exam: exam,
                    examCards: exam.map { e in cards.filter { e.scopeUnitIds.contains($0.unitId) }.count } ?? 0,
                    reviewUnits: reviewUnits,
                    reviewCards: cards.filter { reviewUnits.contains($0.unitId) }.count,
                    groups: groups,
                    withCards: withCards,
                    empty: units(course).filter { !withCards.contains($0.id) }.count,
                    preview: buildDeck(course).count)
    }

    func examDetail(_ pane: Pane) -> String {
        pane.exam.map { String(localized: .quizSolveExamDetail($0.title, pane.examCards)) } ?? String(localized: .quizSolveNoExam)
    }

    func emptyText(_ pane: Pane) -> String {
        String(localized: pane.withCards.isEmpty ? .quizSolveNoCards : .quizSolveEmptyUnits(pane.empty))
    }

    func footer(_ pane: Pane) -> String {
        let categories = scope.categories.isEmpty ? String(localized: .quizSolveAllCategories)
            : CardCategory.allCases.filter(scope.categories.contains).map(\.label).joined(separator: ", ")
        return String(localized: .quizSolveSummary(scope.unitIds.intersection(pane.withCards).count, categories, pane.preview))
    }

    var gradingOptions: [(Grading, String)] {
        let mine = (Grading.mine, String(localized: .quizSolveGradingMine))
        return missingKey ? [mine] : [(.claude, "Claude"), mine]
    }

    func solveOnlyWrong(_ course: LoadedCourse) {
        scope = QuizScope(unitIds: Set(units(course).map(\.id)), onlyWrong: true)
        start(label: String(localized: .quizOnlyWrong), course: course)
    }

    func solveExam(_ pane: Pane, course: LoadedCourse) {
        scope = QuizScope(unitIds: Set(pane.exam?.scopeUnitIds ?? []))
        start(label: String(localized: .quizSolveExamScope), course: course)
    }

    func solveReview(_ pane: Pane, course: LoadedCourse) {
        scope = QuizScope(unitIds: pane.reviewUnits)
        start(label: String(localized: .quizSolveReviewUnits), course: course)
    }

    func allSelected(_ pane: Pane) -> Bool { pane.withCards.isSubset(of: scope.unitIds) }

    func toggleAll(_ pane: Pane, course: LoadedCourse) {
        scope.unitIds = allSelected(pane) ? [] : Set(units(course).map(\.id))
    }

    func toggle(_ unit: UUID) {
        if scope.unitIds.contains(unit) { scope.unitIds.remove(unit) } else { scope.unitIds.insert(unit) }
    }

    func toggle(_ category: CardCategory) {
        if scope.categories.contains(category) { scope.categories.remove(category) } else { scope.categories.insert(category) }
    }

    func unitDetail(_ tally: WrongTally) -> String {
        [String(localized: .quizCardCount(tally.items)),
         tally.accuracy == nil ? nil : String(localized: .quizSolveAccuracy(tally.accuracyText)),
         tally.open > 0 ? String(localized: .quizOpenCount(tally.open)) : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    func unitHelp(_ tally: WrongTally) -> String {
        String(localized: .quizSolveUnitHelp(Int((tally.progress * 100).rounded()), tally.attempted, tally.items))
    }

    func buildDeck(_ course: LoadedCourse) -> [QuizCard] {
        var rng = SystemRandomNumberGenerator()
        return QuizDeck.build(cards: quiz.cards, units: units(course).map(\.id), scope: scope, order: order, history: quiz.history,
                              today: workspace.today, using: &rng)
    }

    func start(label: String, course: LoadedCourse) {
        commit(course)
        self.label = label
        deck = buildDeck(course)
        index = 0
        round = []
        started = true
        resetAnswer()
    }

    func resetAnswer() {
        answer = ""
        revealed = false
        pending = nil
        failure = nil
        busy = false
    }

    // MARK: Card

    var current: QuizCard? { started && index < deck.count ? deck[index] : nil }

    var crumb: String { String(localized: .quizSolveCrumb(label)) }

    func roundText(_ v: Verdict) -> String { "\(v.label) \(round.filter { $0 == v }.count)" }

    var unstartedDetail: String { String(localized: quiz.cards.isEmpty ? .quizSolveNoCardsDetail : .quizSolvePickScopeDetail) }
    var finishedTitle: String { String(localized: deck.isEmpty ? .quizSolveEmptyDeck : .quizSolveEndedEmpty) }
    var finishedDetail: String { String(localized: deck.isEmpty ? .quizSolveEmptyDeckDetail : .quizSolveEndedEmptyDetail) }
    var nextTitle: String { String(localized: index + 1 < deck.count ? .quizSolveNext : .quizSolveDone) }

    func unitTitle(_ card: QuizCard, course: LoadedCourse) -> String {
        units(course).first { $0.id == card.unitId }?.title ?? ""
    }

    func typeText(_ card: QuizCard) -> String {
        card.source == .ai ? String(localized: .quizSolveTypeByClaude(card.type.label)) : card.type.label
    }

    func gradedTitle(_ card: QuizCard, _ p: Pending) -> String {
        String(localized: p.byClaude ? .quizSolveGradedClaude : card.gradesInstantly ? .quizSolveGradedAuto : .quizSolveGradedMine)
    }

    func rubricMet(_ card: QuizCard, _ p: Pending) -> String {
        String(localized: .quizSolveRubricMet(card.rubric.count, card.rubric.count - p.missing.count))
    }

    func extraMissing(_ card: QuizCard, _ p: Pending) -> [String] { p.missing.filter { !card.rubric.contains($0) } }

    var canGrade: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy }

    func choose(_ option: String, on card: QuizCard) {
        let v = card.verdict(choosing: option)
        pending = Pending(cardId: card.id, answer: option, verdict: v, original: v, grader: .self)
    }

    func judge(_ v: Verdict, on card: QuizCard) {
        pending = Pending(cardId: card.id, answer: answer, verdict: v, original: v, grader: .self)
    }

    func grade(_ card: QuizCard, course: LoadedCourse) {
        guard workspace.claudeReady else {
            missingKey = true
            failure = ""
            return
        }
        busy = true
        failure = nil
        let client = workspace.claude(for: course)
        let given = answer
        Task {
            do {
                let r = try await client.grade(question: card.prompt, modelAnswer: card.answer, rubric: card.rubric, answer: given, rules: "")
                let v = Verdict(rawValue: r.verdict.rawValue) ?? .wrong
                pending = Pending(cardId: card.id, answer: given, verdict: v, original: v, grader: .ai, missing: r.missing, feedback: r.feedback, byClaude: true)
            } catch ClaudeError.missingAPIKey {
                missingKey = true
                failure = ""
            } catch {
                failure = String(localized: .quizSolveGradeFailed("\(error)"))
            }
            busy = false
        }
    }

    func next(_ course: LoadedCourse) {
        commit(course)
        index += 1
        resetAnswer()
    }

    func finish(_ course: LoadedCourse) {
        commit(course)
        index = deck.count
    }

    func commit(_ course: LoadedCourse) {
        guard let p = pending else { return }
        workspace.run(QuizRecord(course: course.id, attempt: QuizAttemptEvent(cardId: p.cardId, answer: p.answer.isEmpty ? nil : p.answer, verdict: p.verdict,
                                                                         grader: p.grader, missing: p.missing, overridden: p.verdict != p.original)))
        round.append(p.verdict)
        pending = nil
        quiz.load(course)
    }

    // MARK: History

    func past(_ card: QuizCard) -> [Attempt<QuizAttemptEvent>] { quiz.attempts.filter { $0.event.cardId == card.id } }

    func historyDetail(_ a: Attempt<QuizAttemptEvent>) -> String {
        ([a.at.monthDay, a.event.grader == .ai ? "Claude" : String(localized: .quizSolveGradingMine)]
            + (a.event.overridden ? [String(localized: .quizSolveOverridden)] : [])).joined(separator: " · ")
    }
}
