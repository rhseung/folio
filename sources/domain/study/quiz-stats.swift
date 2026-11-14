import Algorithms
import Foundation

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
