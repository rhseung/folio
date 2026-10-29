import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct Attempt<Event: LogEvent> {
    var at: Date
    var day: LocalDate
    var event: Event
}

struct SolveRequest: Equatable {
    var id = UUID()
    var scope: QuizScope
    var label: String
    var order: QuizOrder = .unitOrder
}

/// The course's cards and attempts, read once and re-read after each write so every tab shows the same numbers.
/// The course comes from the view on each call: kept here, it went stale after every write that reloads it.
@MainActor @Observable
final class QuizModel {
    let workspace: Workspace
    var cards: [QuizCard] = []
    var attempts: [Attempt<QuizAttemptEvent>] = []
    var problemAttempts: [Attempt<ProblemAttemptEvent>] = []
    private(set) var history: [UUID: AttemptHistory] = [:]
    private(set) var problemHistory: [String: AttemptHistory] = [:]
    /// A request is for the solve screen it opens; kept, it restarted that deck whenever 풀기 was chosen again.
    var request: SolveRequest?
    var generating: FolioDomain.Unit?
    var editing: CardDraft?
    var removingCard: QuizCard?
    var removingSet: ProblemSet?

    init(workspace: Workspace) { self.workspace = workspace }

    func load(_ course: LoadedCourse) {
        cards = UnitTree.outline(course.file.units).flatMap { (try? course.store.loadQuiz(unit: $0.unit.id).model.cards) ?? [] }
        attempts = Self.attempts(QuizAttemptEvent.self, in: course, workspace)
        problemAttempts = Self.attempts(ProblemAttemptEvent.self, in: course, workspace)
        history = Dictionary(grouping: attempts, by: \.event.cardId).mapValues { $0.map { ($0.day, $0.event.verdict) } }
        problemHistory = Dictionary(grouping: problemAttempts) { Self.key($0.event.problemSetId, $0.event.number) }
            .mapValues { $0.map { ($0.day, $0.event.verdict) } }
    }

    private static func attempts<E: LogEvent>(_: E.Type, in course: LoadedCourse, _ workspace: Workspace) -> [Attempt<E>] {
        ((try? course.store.log.readAll()) ?? []).events(E.self).map {
            Attempt(at: $0.at, day: workspace.settings.studyDay(of: $0.at, calendar: workspace.calendar), event: $0.event)
        }
    }

    static func key(_ set: UUID, _ number: String) -> String { "\(set.uuidString)/\(number)" }

    func history(of card: UUID) -> AttemptHistory { history[card] ?? [] }
    func history(set: UUID, number: String) -> AttemptHistory { problemHistory[Self.key(set, number)] ?? [] }
    func isOpen(_ card: QuizCard) -> Bool { WrongFlow.isOpen(WrongFlow.status(history(of: card.id))) }

    // MARK: Cards

    enum Entry: Identifiable {
        case unit(FolioDomain.Unit, depth: Int, cards: Int)
        case card(QuizCard, depth: Int)
        var id: UUID {
            switch self {
            case .unit(let u, _, _): u.id
            case .card(let c, _): c.id
            }
        }
    }

    struct CardGroup: Identifiable {
        var id: Int
        var root: FolioDomain.Unit?
        var count: Int
        var entries: [Entry]
    }

    func cardsSubtitle(_ course: LoadedCourse) -> String {
        let open = cards.filter(isOpen).count
        return ([String(localized: .quizCardsCardCount(cards.count)), String(localized: .quizCardsUnitCount(course.outline.count))]
            + (open > 0 ? [String(localized: .quizCardsWrongCount(open))] : [])).joined(separator: " · ")
    }

    func cardGroups(_ course: LoadedCourse) -> [CardGroup] {
        let byUnit = Dictionary(grouping: cards, by: \.unitId)
        return UnitsView.groups(course.outline).enumerated().map { i, group in
            let entries = (group.root.map { byUnit[$0.id] ?? [] } ?? []).map { Entry.card($0, depth: 0) }
                + group.rows.flatMap { row in
                    [Entry.unit(row.unit, depth: row.depth, cards: byUnit[row.unit.id]?.count ?? 0)]
                        + (byUnit[row.unit.id] ?? []).map { .card($0, depth: row.depth + 1) }
                }
            let count = ((group.root.map { [$0.id] } ?? []) + group.rows.map(\.unit.id)).reduce(0) { $0 + (byUnit[$1]?.count ?? 0) }
            return CardGroup(id: i, root: group.root, count: count, entries: entries)
        }
    }

    func unitCardsText(_ n: Int) -> String { String(localized: n > 0 ? .quizCardCount(n) : .quizCardsNone) }

    func detail(_ card: QuizCard) -> String {
        [card.type.label, card.category.label, card.source == .ai ? "Claude" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    func removeCard(in course: LoadedCourse) {
        if let card = removingCard { workspace.run(QuizCardRemove(course: course.id, unit: card.unitId, card: card.id)) }
        load(course)
        removingCard = nil
    }

    // MARK: Statistics

    struct Stats {
        var units: [FolioDomain.Unit]
        var total: WrongTally
        var byUnit: [UUID: WrongTally]
        var byCategory: [CardCategory: WrongTally]
        var due: [QuizCard]
        var solvedToday: Int
        /// Only units with cards: forty rows of zeros buried the few that mean something.
        var shownUnits: [FolioDomain.Unit] { units.filter { byUnit[$0.id] != nil } }
        var categories: [CardCategory] { CardCategory.allCases.filter { byCategory[$0] != nil } }
    }

    func stats(_ course: LoadedCourse) -> Stats {
        let today = workspace.today
        let history = { (card: QuizCard) in self.history(of: card.id) }
        return Stats(units: course.outline.map(\.unit),
                     total: QuizStats.total(cards, history: history),
                     byUnit: QuizStats.tally(cards, keys: { [$0.unitId] }, history: history),
                     byCategory: QuizStats.tally(cards, keys: { [$0.category] }, history: history),
                     due: cards.filter { WrongFlow.isDue(history($0), today: today) },
                     solvedToday: attempts.filter { $0.day == today }.count + problemAttempts.filter { $0.day == today }.count)
    }

    func dueDetail(_ card: QuizCard, units: [FolioDomain.Unit]) -> String {
        [units.first { $0.id == card.unitId }?.title, card.category.label].compactMap { $0 }.joined(separator: " · ")
    }

    func dueChip(_ card: QuizCard) -> (text: String, tone: Tone) {
        switch WrongFlow.status(history(of: card.id)) {
        case .open(let since): (String(localized: .quizStatsOpenSince(since.short)), .danger)
        default: (String(localized: .quizStatsRecheck), .warning)
        }
    }

    var dueEmpty: String { String(localized: attempts.isEmpty ? .quizStatsNoneSolved : .quizStatsNoneOpen) }

    func solveAllWrong(_ units: [FolioDomain.Unit]) -> SolveRequest {
        SolveRequest(scope: QuizScope(unitIds: Set(units.map(\.id)), onlyWrong: true), label: String(localized: .quizOnlyWrong))
    }

    func solveWrong(of unit: UUID, units: [FolioDomain.Unit]) -> SolveRequest {
        SolveRequest(scope: QuizScope(unitIds: [unit], onlyWrong: true),
                     label: String(localized: .quizStatsWrongOf(units.first { $0.id == unit }?.title ?? "")))
    }

    /// The last fourteen study days, oldest first, with the attempts on each (problems included).
    func dailyCounts(today: LocalDate) -> [(day: LocalDate, count: Int)] {
        let counts = Dictionary((attempts.map(\.day) + problemAttempts.map(\.day)).map { ($0, 1) }, uniquingKeysWith: +)
        return (0..<14).reversed().map { today.adding(days: -$0) }.map { ($0, counts[$0] ?? 0) }
    }

    // MARK: Problem sets

    typealias ProblemRef = (set: UUID, problem: ProblemSet.Problem)

    func problemsSubtitle(_ course: LoadedCourse) -> String {
        let sets = course.file.problemSets
        guard !sets.isEmpty else { return String(localized: .quizProblemsSubtitleEmpty) }
        let total = problemTotal(sets)
        return ([String(localized: .quizProblemsSetCount(sets.count)), String(localized: .quizProblemsProblemCount(total.items)),
                 String(localized: .quizProblemsAttemptedCount(total.attempted))]
            + (total.open > 0 ? [String(localized: .quizProblemsOpenCount(total.open))] : [])).joined(separator: " · ")
    }

    private func problems(_ sets: [ProblemSet]) -> [ProblemRef] { sets.flatMap { s in s.problems.map { (set: s.id, problem: $0) } } }
    private func attemptsOf(_ p: ProblemRef) -> AttemptHistory { history(set: p.set, number: p.problem.number) }
    private func problemTotal(_ sets: [ProblemSet]) -> WrongTally { QuizStats.total(problems(sets), history: attemptsOf) }

    func problemsByUnit(_ course: LoadedCourse) -> (units: [FolioDomain.Unit], tally: [UUID: WrongTally]) {
        let byUnit = QuizStats.tally(problems(course.file.problemSets), keys: \.problem.unitIds, history: attemptsOf)
        return (course.outline.map(\.unit).filter { byUnit[$0.id] != nil }, byUnit)
    }

    func summary(_ set: ProblemSet) -> String {
        let t = QuizStats.total(set.problems) { self.history(set: set.id, number: $0.number) }
        return ([String(localized: .quizProblemsItems(t.items)), String(localized: .quizProblemsCorrectCount(t.correct)),
                 String(localized: .quizProblemsWrongCount(t.open)), String(localized: .quizResolvedCount(t.resolved))]
            + (t.items > t.attempted ? [String(localized: .quizProblemsUnsolvedCount(t.items - t.attempted))] : []))
            .joined(separator: " · ")
    }

    func material(_ id: UUID?, in course: LoadedCourse) -> FolioDomain.Material? {
        id.flatMap { id in course.file.materials.first { $0.id == id } }
    }

    func linkedTitles(_ problem: ProblemSet.Problem, units: [FolioDomain.Unit]) -> String {
        units.filter { problem.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ")
    }

    func historyLine(_ history: AttemptHistory) -> String {
        history.map { "\($0.day.short) \($0.verdict.label)" }.joined(separator: " · ")
    }

    func record(_ verdict: Verdict, set: UUID, number: String, in course: LoadedCourse) {
        workspace.run(ProblemRecord(course: course.id, attempt: ProblemAttemptEvent(problemSetId: set, number: number, verdict: verdict)))
        load(course)
    }

    func toggle(_ unit: UUID, set: UUID, problem: ProblemSet.Problem, in course: LoadedCourse) {
        workspace.run(ProblemLinkUnit(course: course.id, set: set, number: problem.number, unit: unit, linked: !problem.unitIds.contains(unit)))
    }

    func removeSet(in course: LoadedCourse) {
        if let set = removingSet { workspace.run(ProblemSetRemove(course: course.id, set: set.id)) }
        removingSet = nil
    }
}
