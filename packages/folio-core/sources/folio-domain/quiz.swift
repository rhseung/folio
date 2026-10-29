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

/// `.folio/quizzes/<unit ID>.json` holds one unit's cards (docs/SPEC.md "QuizCard").
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
    /// Widget ID or image path.
    public var figure: String?
    public var options: [String]
    public var answer: String
    /// Elements whose absence makes an answer wrong.
    public var rubric: [String]
    public var source: CardSource
    public var sourceMaterialId: UUID?
    public var sourceProblem: String?
    /// The note block the card was made from; a changed block marks the card "원본 변경됨".
    public var noteId: UUID?
    public var noteBlockId: String?
    public var noteBlockHash: String?

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, unitId: UUID, type: CardType, category: CardCategory,
                prompt: String, options: [String] = [], answer: String, rubric: [String] = [], source: CardSource = .manual) {
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

/// `quiz_attempt` log event.
public struct QuizAttemptEvent: LogEvent, Equatable {
    public static let type = "quiz_attempt"
    public var cardId: UUID
    public var answer: String?
    public var inkId: UUID?
    public var verdict: Verdict
    public var grader: Grader
    public var missing: [String]
    /// The user changed the grader's verdict; statistics use the changed one (`verdict`).
    public var overridden: Bool
    public var hintUsed: Bool

    public enum Grader: String, Codable, Sendable, CaseIterable { case ai, `self` }

    public init(cardId: UUID, answer: String? = nil, inkId: UUID? = nil, verdict: Verdict, grader: Grader, missing: [String] = [], overridden: Bool = false, hintUsed: Bool = false) {
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

/// `problem_attempt` log event for numbered problems solved on paper or in ink.
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

/// Problem sets, past exams, textbook exercises: numbered problems tracked like cards (docs/SPEC.md "ProblemSet").
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

/// The wrong-answer flow (docs/SPEC.md "오답 흐름") for cards and problems alike.
public enum WrongStatus: Equatable, Sendable {
    case neverWrong
    /// Wrong or partial and not yet answered correctly since.
    case open(since: LocalDate)
    /// Answered correctly after being wrong; checked once more 7 days later.
    case resolved(on: LocalDate, recheckDue: LocalDate?)
}

public enum WrongFlow {
    public static let recheckAfterDays = 7

    /// Status after a time-ordered list of (study day, verdict).
    public static func status(_ attempts: [(day: LocalDate, verdict: Verdict)]) -> WrongStatus {
        var status = WrongStatus.neverWrong
        for (day, verdict) in attempts {
            switch (status, verdict) {
            case (_, .wrong), (_, .partial):
                status = .open(since: day)
            case (.open, .correct):
                status = .resolved(on: day, recheckDue: day.adding(days: recheckAfterDays))
            case (.resolved(let on, let due?), .correct) where day >= due:
                status = .resolved(on: on, recheckDue: nil)  // passed the recheck
            default:
                break
            }
        }
        return status
    }

    /// Belongs in the wrong list today: still open, or resolved with its 7-day recheck reached.
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

    /// Up to `count` cards for a review: open wrong cards first (oldest first), then the longest unattempted.
    public static func pickForReview(cards: [UUID], attempts: [UUID: [(day: LocalDate, verdict: Verdict)]], today: LocalDate, count: Int) -> [UUID] {
        func lastDay(_ id: UUID) -> LocalDate? { attempts[id]?.last?.day }
        let due = cards.filter { isDue(attempts[$0] ?? [], today: today) }
        let rest = cards.filter { !due.contains($0) }.sorted { (lastDay($0) ?? .init(year: 1, month: 1, day: 1)!) < (lastDay($1) ?? .init(year: 1, month: 1, day: 1)!) }
        return Array((due + rest).prefix(count))
    }

    /// Correct share of attempts, counting partial as half.
    public static func accuracy(_ verdicts: [Verdict]) -> Double? {
        guard !verdicts.isEmpty else { return nil }
        let score = verdicts.reduce(0.0) { $0 + ($1 == .correct ? 1 : $1 == .partial ? 0.5 : 0) }
        return score / Double(verdicts.count)
    }
}
