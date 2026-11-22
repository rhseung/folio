import FolioCore
import Foundation

// 한 과목의 공부를 모두 센다. 화면과 CLI는 이것만 읽고 규칙을 다시 적지 않는다.
public struct CourseStudy: Sendable {
    public struct ProblemRecord: Sendable, Equatable {
        public var setId: UUID
        public var problem: Problem
        public var source: ProblemSource
        public var attempts: [ProblemAttempt]
        public var status: WrongStatus

        public var last: ProblemAttempt? { attempts.last }
        public var solved: Bool { !attempts.isEmpty }
    }

    public struct CardRecord: Sendable, Equatable {
        public var card: StudyCard
        public var flips: [(day: LocalDate, known: Bool)]
        public var status: WrongStatus

        public static func == (a: Self, b: Self) -> Bool {
            a.card == b.card && a.status == b.status && a.flips.map(\.day) == b.flips.map(\.day)
                && a.flips.map(\.known) == b.flips.map(\.known)
        }
    }

    public let file: CourseFile
    public let today: LocalDate
    public let settings: StudySettings
    public private(set) var problems: [UUID: ProblemRecord] = [:]
    public private(set) var problemOrder: [UUID] = []
    public private(set) var cards: [UUID: CardRecord] = [:]
    public private(set) var cardOrder: [UUID] = []
    public private(set) var seen: [UUID: Set<Int>] = [:]
    public private(set) var manualChecks: Set<UUID> = []
    // 풀기가 끝난 묶음이다. 섞어 풀기와 모의시험 항목이 이것으로 체크된다.
    public private(set) var runs: Set<UUID> = []

    public init(
        file: CourseFile, cards: [StudyCard], log: StudyLog, settings: Settings, calendar: Calendar, now: Date
    ) {
        self.file = file
        self.settings = settings.study
        let day = { (date: Date) in settings.studyDay(of: date, calendar: calendar) }
        today = day(now)

        let changes = Dictionary(
            log.changes.sorted { $0.at < $1.at }.map { ($0.event.attemptId, $0.event) }, uniquingKeysWith: { _, b in b })
        var attempts: [UUID: [ProblemAttempt]] = [:]
        for (at, e) in log.solves.sorted(by: { $0.at < $1.at }) {
            attempts[e.problemId, default: []].append(ProblemAttempt(e, at: at, day: day(at), change: changes[e.id]))
            if let run = e.runId { runs.insert(run) }
        }
        for set in file.problemSets {
            for p in set.problems {
                let tries = attempts[p.id] ?? []
                problems[p.id] = ProblemRecord(
                    setId: set.id, problem: p, source: set.source, attempts: tries,
                    status: WrongFlow.status(tries.map { ($0.day, !$0.verdict.isMistake) }))
                problemOrder.append(p.id)
            }
        }

        var flips: [UUID: [(LocalDate, Bool)]] = [:]
        for (at, e) in log.flips.sorted(by: { $0.at < $1.at }) { flips[e.cardId, default: []].append((day(at), e.known)) }
        for card in cards {
            let f = flips[card.id] ?? []
            self.cards[card.id] = CardRecord(card: card, flips: f.map { (day: $0.0, known: $0.1) }, status: WrongFlow.status(f))
            cardOrder.append(card.id)
        }

        for (_, v) in log.views { seen[v.materialId, default: []].insert(v.page) }
        manualChecks = ExamPlan.done(log.checks)
    }

    // MARK: Problems

    public var allProblems: [ProblemRecord] { problemOrder.compactMap { problems[$0] } }

    public func problems(of unit: UUID) -> [ProblemRecord] { allProblems.filter { $0.problem.unitIds.contains(unit) } }

    public func problems(inSet set: UUID) -> [ProblemRecord] { allProblems.filter { $0.setId == set } }

    // MARK: Cards

    public var allCards: [CardRecord] { cardOrder.compactMap { cards[$0] } }

    public func cards(of unit: UUID) -> [CardRecord] { allCards.filter { $0.card.unitId == unit } }

    // 넘겨 보기는 모르는 카드, 처음 보는 카드, 아는 카드 순이다. 같은 무리 안에서는 만든 순서를 지킨다.
    public func flipDeck(unit: UUID?) -> [CardRecord] {
        let records = unit.map(cards(of:)) ?? allCards
        func rank(_ s: WrongStatus) -> Int { s.needsWork ? 0 : s == .untried ? 1 : 2 }
        return records.enumerated().sorted { a, b in
            rank(a.element.status) != rank(b.element.status) ? rank(a.element.status) < rank(b.element.status) : a.offset < b.offset
        }
        .map(\.element)
    }

    // MARK: Units

    public func readiness(of unit: UUID) -> UnitReadiness {
        let records = problems(of: unit)
        let items = records.map { Readiness.Item(verdict: $0.last?.verdict, basis: $0.last?.basis, status: $0.status) }
        let concept = records.filter { $0.status.needsWork && $0.last?.reason == .concept }.flatMap(\.problem.lecturePages)
        return UnitReadiness(
            state: Readiness.state(items, readyScore: settings.readyScore, minProblems: settings.minProblems),
            score: Readiness.score(items), problems: records.count, judged: records.filter(\.solved).count,
            wrong: records.filter(\.status.isOpen).count, recheck: records.filter(\.status.isRecheck).count,
            pastExam: records.filter { $0.source == .pastExam }.count, conceptPages: Array(Set(concept)).sorted { ($0.page) < ($1.page) })
    }

    public func progress(of unit: Unit, notes: Int) -> UnitProgress {
        let ranges = unit.lecturePages
        let total = ranges.reduce(0) { $0 + $1.pages.count }
        let inRange = ranges.reduce(0) { n, r in n + (seen[r.materialId] ?? []).filter { r.pages.contains($0) }.count }
        let linked = file.materials.filter { $0.unitIds.contains(unit.id) && !ranges.map(\.materialId).contains($0.id) }
        let other = linked.reduce(0) { $0 + (seen[$1.id]?.count ?? 0) }
        let probs = problems(of: unit.id)
        let cs = cards(of: unit.id)
        return UnitProgress(
            unitId: unit.id, done: unit.isDone, pagesSeen: inRange, pagesTotal: total, otherPagesSeen: other, notes: notes,
            problemsSolved: probs.filter(\.solved).count, problemsTotal: probs.count, problemsWrong: probs.filter(\.status.needsWork).count,
            cardsFlipped: cs.filter { !$0.flips.isEmpty }.count, cardsTotal: cs.count, cardsUnknown: cs.filter(\.status.needsWork).count,
            readiness: readiness(of: unit.id))
    }

    public func seenPages(of material: UUID) -> Set<Int> { seen[material] ?? [] }
}
