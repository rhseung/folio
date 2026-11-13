import Foundation

public enum CardType: String, Codable, Sendable, CaseIterable {
    case free, trueFalse = "true_false", choice, fill, proof, handwritten
}

public enum CardCategory: String, Codable, Sendable, CaseIterable {
    case definition, theorem, proof, counterexample, computation, concept, design
}

public enum CardSource: String, Codable, Sendable, CaseIterable {
    case ai, manual, material
}

public struct QuizFile: Codable, Sendable, Equatable {
    public var unitId: UUID
    public var cards: [QuizCard]

    public init(unitId: UUID, cards: [QuizCard] = []) {
        self.unitId = unitId
        self.cards = cards
    }
}

public struct QuizCard: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var unitId: UUID
    public var type: CardType
    public var category: CardCategory
    public var prompt: String
    public var figure: String?
    public var options: [String]
    public var answer: String
    public var rubric: [String]
    public var source: CardSource
    public var sourceMaterialId: UUID?
    public var sourceProblem: String?
    public var noteId: UUID?
    public var noteBlockId: String?
    public var noteBlockHash: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, unitId: UUID, type: CardType, category: CardCategory,
        prompt: String, options: [String] = [], answer: String, rubric: [String] = [], source: CardSource = .manual
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.unitId = unitId
        self.type = type
        self.category = category
        self.prompt = prompt
        self.options = options
        self.answer = answer
        self.rubric = rubric
        self.source = source
    }
}

public enum Verdict: String, Codable, Sendable, CaseIterable {
    case correct, partial, wrong
}

public struct QuizAttemptEvent: LogEvent, Equatable {
    public static let type = "quiz_attempt"
    public var cardId: UUID
    public var answer: String?
    public var inkId: UUID?
    public var verdict: Verdict
    public var grader: Grader
    public var missing: [String]
    public var overridden: Bool
    public var hintUsed: Bool

    public enum Grader: String, Codable, Sendable, CaseIterable { case ai, `self` }

    public init(
        cardId: UUID, answer: String? = nil, inkId: UUID? = nil, verdict: Verdict, grader: Grader, missing: [String] = [],
        overridden: Bool = false, hintUsed: Bool = false
    ) {
        self.cardId = cardId
        self.answer = answer
        self.inkId = inkId
        self.verdict = verdict
        self.grader = grader
        self.missing = missing
        self.overridden = overridden
        self.hintUsed = hintUsed
    }
}

public struct ProblemAttemptEvent: LogEvent, Equatable {
    public static let type = "problem_attempt"
    public var problemSetId: UUID
    public var number: String
    public var verdict: Verdict
    public var inkId: UUID?

    public init(problemSetId: UUID, number: String, verdict: Verdict, inkId: UUID? = nil) {
        self.problemSetId = problemSetId
        self.number = number
        self.verdict = verdict
        self.inkId = inkId
    }
}

public struct ProblemSet: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public struct Problem: Codable, Sendable, Equatable {
        public var number: String
        public var page: Int?
        public var unitIds: [UUID]
        public var category: CardCategory?

        public init(number: String, page: Int? = nil, unitIds: [UUID] = [], category: CardCategory? = nil) {
            self.number = number
            self.page = page
            self.unitIds = unitIds
            self.category = category
        }
    }

    public var title: String
    public var materialId: UUID?
    public var solutionMaterialId: UUID?
    public var problems: [Problem]

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, problems: [Problem] = []) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.problems = problems
    }
}

public enum WrongStatus: Equatable, Sendable {
    case neverWrong
    case open(since: LocalDate)
    case resolved(on: LocalDate, recheckDue: LocalDate?)
}

public enum WrongFlow {
    public static let recheckAfterDays = 7

    public static func status(_ attempts: [(day: LocalDate, verdict: Verdict)]) -> WrongStatus {
        var status = WrongStatus.neverWrong
        for (day, verdict) in attempts {
            switch (status, verdict) {
            case (_, .wrong), (_, .partial):
                status = .open(since: day)
            case (.open, .correct):
                status = .resolved(on: day, recheckDue: day.adding(days: recheckAfterDays))
            case (.resolved(let on, let due?), .correct) where day >= due:
                status = .resolved(on: on, recheckDue: nil)
            default:
                break
            }
        }
        return status
    }

    public static func isDue(_ attempts: [(day: LocalDate, verdict: Verdict)], today: LocalDate) -> Bool {
        switch status(attempts) {
        case .open: true
        case .resolved(_, let recheck?): recheck <= today
        default: false
        }
    }

    public static func isOpen(_ s: WrongStatus) -> Bool {
        if case .open = s { true } else { false }
    }

    public static func pickForReview(cards: [UUID], attempts: [UUID: [(day: LocalDate, verdict: Verdict)]], today: LocalDate, count: Int)
        -> [UUID]
    {
        func lastDay(_ id: UUID) -> LocalDate? { attempts[id]?.last?.day }
        let due = cards.filter { isDue(attempts[$0] ?? [], today: today) }
        let rest = cards.filter { !due.contains($0) }.sorted {
            (lastDay($0) ?? .init(year: 1, month: 1, day: 1)!) < (lastDay($1) ?? .init(year: 1, month: 1, day: 1)!)
        }
        return Array((due + rest).prefix(count))
    }

    public static func accuracy(_ verdicts: [Verdict]) -> Double? {
        guard !verdicts.isEmpty else { return nil }
        let score = verdicts.reduce(0.0) { $0 + ($1 == .correct ? 1 : $1 == .partial ? 0.5 : 0) }
        return score / Double(verdicts.count)
    }
}
