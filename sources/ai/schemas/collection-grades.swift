import FolioCore
import FolioDomain
import Foundation

// 푼 문제집 한 벌의 채점이다. `item`은 보낸 문제 목록의 차례(1부터)이고, `page`는 그 풀이를 찾은 낸 PDF의 쪽이다.
public struct CollectionGrades: StructuredResult, Equatable {
    public struct Grade: Codable, Sendable, Equatable {
        public var item: Int
        public var verdict: Verdict
        public var reason: WrongReason?
        public var feedback: [String]
        public var page: Int?

        public init(item: Int, verdict: Verdict, reason: WrongReason? = nil, feedback: [String] = [], page: Int? = nil) {
            self.item = item
            self.verdict = verdict
            self.reason = reason
            self.feedback = feedback
            self.page = page
        }
    }

    public var grades: [Grade]

    public init(grades: [Grade]) { self.grades = grades }

    public static let schema = Schema.object([
        "grades": Schema.array(
            Schema.object([
                "item": Schema.integer,
                "verdict": Schema.enumeration(["correct", "partial", "wrong"]),
                "reason": Schema.nullable(Schema.enumeration(WrongReason.allCases.map(\.rawValue))),
                "feedback": Schema.array(Schema.string),
                "page": Schema.nullable(Schema.integer),
            ]))
    ])
}
