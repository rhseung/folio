import Foundation

public struct PlannedMove: Codable, Sendable, Hashable {
    public var from: String
    public var to: String
    public var review: ReviewReason?
    public var exam: String?
    public var kind: MaterialKind?

    public init(from: String, to: String, review: ReviewReason? = nil, exam: String? = nil, kind: MaterialKind? = nil) {
        self.from = from
        self.to = to
        self.review = review
        self.exam = exam
        self.kind = kind
    }
}
