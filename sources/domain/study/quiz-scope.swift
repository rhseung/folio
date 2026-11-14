import Algorithms
import Foundation

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
