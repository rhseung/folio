import Foundation

public struct ReviewSettings: Codable, Sendable, Equatable {
    public var intervals: [Int]
    public var settleAfterPasses: Int
    public var dailyLimit: Int?
    public var examWindowDays: Int
    public var cardsPerReview: Int
    public var weights: PriorityWeights

    public init(
        intervals: [Int] = [1, 3, 7, 14, 30], settleAfterPasses: Int = 2, dailyLimit: Int? = nil,
        examWindowDays: Int = 7, cardsPerReview: Int = 5, weights: PriorityWeights = .init()
    ) {
        self.intervals = intervals
        self.settleAfterPasses = settleAfterPasses
        self.dailyLimit = dailyLimit
        self.examWindowDays = examWindowDays
        self.cardsPerReview = cardsPerReview
        self.weights = weights
    }

    public func interval(atStep step: Int) -> Int { intervals[min(max(step, 0), intervals.count - 1)] }

    public func reviewDays(after day: LocalDate) -> [LocalDate] {
        var next = day
        return intervals.map {
            next = next.adding(days: $0); return next
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReviewSettings()
        // 모든 단계를 인덱스로 쓰고 나눗셈에도 쓰므로, 손으로 고친 목록이 비었거나 양수가 아니면 기본값으로 돌아간다.
        let decoded = try c.decodeIfPresent([Int].self, forKey: .intervals)?.filter { $0 > 0 } ?? []
        intervals = decoded.isEmpty ? d.intervals : decoded
        settleAfterPasses = try c.decodeIfPresent(Int.self, forKey: .settleAfterPasses) ?? d.settleAfterPasses
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit)
        examWindowDays = try c.decodeIfPresent(Int.self, forKey: .examWindowDays) ?? d.examWindowDays
        cardsPerReview = try c.decodeIfPresent(Int.self, forKey: .cardsPerReview) ?? d.cardsPerReview
        weights = try c.decodeIfPresent(PriorityWeights.self, forKey: .weights) ?? d.weights
    }
}
