import Foundation

public struct ExamPlanTarget: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case unit
        // 문제 묶음 하나, `problemIds`가 있으면 그 문제들이다.
        case problems
        // 범위 단원의 문제를 섞어 푼다.
        case mixed
        case mock
        // 남은 오답과 모른 카드를 푼다.
        case wrong
        // 사용자가 쓴 할 일이다.
        case custom

        // 날마다 하나만 있으면 되는 종류다. 다시 짤 때 사용자가 옮긴 것이 있으면 새로 넣지 않는다.
        public var isFinal: Bool { self == .mixed || self == .mock || self == .wrong }
    }

    public var kind: Kind
    public var id: UUID?
    public var problemIds: [UUID]?

    public init(kind: Kind, id: UUID? = nil, problemIds: [UUID]? = nil) {
        self.kind = kind
        self.id = id
        self.problemIds = problemIds
    }

    public static func unit(_ id: UUID) -> ExamPlanTarget { ExamPlanTarget(kind: .unit, id: id) }
}
