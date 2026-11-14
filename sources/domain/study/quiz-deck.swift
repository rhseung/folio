import Algorithms
import Foundation

public typealias AttemptHistory = [(day: LocalDate, verdict: Verdict)]

public struct WrongTally: Equatable, Sendable {
    public var items = 0
    public var attempted = 0
    public var correct = 0
    public var open = 0
    public var resolved = 0
    public var verdicts: [Verdict] = []

    public init() {}

    public var accuracy: Double? { WrongFlow.accuracy(verdicts) }
    public var progress: Double { items == 0 ? 0 : Double(attempted) / Double(items) }

    mutating func add(_ history: AttemptHistory) {
        items += 1
        verdicts += history.map(\.verdict)
        if !history.isEmpty { attempted += 1 }
        switch WrongFlow.status(history) {
        case .open: open += 1
        case .resolved: resolved += 1
        case .neverWrong: if !history.isEmpty { correct += 1 }
        }
    }
}

public enum QuizStats {
    public static func tally<Item, Key: Hashable>(_ items: [Item], keys: (Item) -> [Key], history: (Item) -> AttemptHistory) -> [Key:
        WrongTally]
    {
        var result: [Key: WrongTally] = [:]
        for item in items {
            let h = history(item)
            for key in keys(item) { result[key, default: WrongTally()].add(h) }
        }
        return result
    }

    public static func total<Item>(_ items: [Item], history: (Item) -> AttemptHistory) -> WrongTally {
        tally(items, keys: { _ in [0] }, history: history)[0] ?? WrongTally()
    }
}

public enum QuizOrder: String, CaseIterable, Sendable {
    case unitOrder, random, wrongFirst
}

public struct QuizScope: Equatable, Sendable {
    public var unitIds: Set<UUID>
    public var categories: Set<CardCategory>
    public var onlyWrong: Bool

    public init(unitIds: Set<UUID> = [], categories: Set<CardCategory> = [], onlyWrong: Bool = false) {
        self.unitIds = unitIds
        self.categories = categories
        self.onlyWrong = onlyWrong
    }
}

public enum QuizDeck {
    public static func build(
        cards: [QuizCard], units: [UUID], scope: QuizScope, order: QuizOrder,
        history: [UUID: AttemptHistory], today: LocalDate,
        using rng: inout some RandomNumberGenerator
    ) -> [QuizCard] {
        let rank = Dictionary(units.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let due = { (card: QuizCard) in WrongFlow.isDue(history[card.id] ?? [], today: today) }
        let picked = cards.enumerated()
            .filter { scope.unitIds.contains($0.element.unitId) }
            .filter { scope.categories.isEmpty || scope.categories.contains($0.element.category) }
            .filter { !scope.onlyWrong || due($0.element) }
            .sorted { (rank[$0.element.unitId] ?? .max, $0.offset) < (rank[$1.element.unitId] ?? .max, $1.offset) }
            .map(\.element)
        switch order {
        case .unitOrder: return picked
        case .random: return picked.shuffled(using: &rng)
        case .wrongFirst: return picked.filter(due) + picked.filter { !due($0) }
        }
    }
}

extension QuizCard {
    public static let trueFalseOptions = ["참", "거짓"]

    public var gradesInstantly: Bool { type == .trueFalse || type == .choice }

    public func verdict(choosing option: String) -> Verdict {
        option == answer ? .correct : .wrong
    }
}

extension ProblemSet {
    // 오타로 수천 개가 생기지 않도록, 범위는 숫자만 받고 개수를 제한한다.
    public static func numbers(from text: String) -> [String] {
        var result: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            if ends.count == 2, part.split(separator: "-").count == 2, ends[0] <= ends[1], ends[1] - ends[0] < 500 {
                result += (ends[0]...ends[1]).map(String.init)
            } else {
                result.append(part)
            }
        }
        return Array(result.uniqued())
    }
}
