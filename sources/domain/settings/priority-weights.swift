import Foundation

public struct PriorityWeights: Codable, Sendable, Equatable {
    public var overdue: Double
    public var exam: Double
    public var quizMiss: Double
    public var openWrong: Double

    public init(overdue: Double = 1, exam: Double = 3, quizMiss: Double = 1, openWrong: Double = 0.2) {
        self.overdue = overdue
        self.exam = exam
        self.quizMiss = quizMiss
        self.openWrong = openWrong
    }
}
