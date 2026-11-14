import Algorithms
import Foundation

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
