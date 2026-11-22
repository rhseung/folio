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
    // 하루 항목 수(`study.planDayItems`)를 넘는 날의 단원을 한 항목으로 묶은 것이다. `id`는 그 첫 단원이라, 단원 하나를 읽는 곳과 첫
    // 단원을 지울 때 항목을 지우는 규칙이 그대로 맞는다.
    public var unitIds: [UUID]?

    public init(kind: Kind, id: UUID? = nil, problemIds: [UUID]? = nil, unitIds: [UUID]? = nil) {
        self.kind = kind
        self.id = id
        self.problemIds = problemIds
        self.unitIds = unitIds
    }

    public static func unit(_ id: UUID) -> ExamPlanTarget { ExamPlanTarget(kind: .unit, id: id) }

    public static func units(_ ids: [UUID]) -> ExamPlanTarget {
        ids.count == 1 ? .unit(ids[0]) : ExamPlanTarget(kind: .unit, id: ids.first, unitIds: ids)
    }

    // 단원 항목이 가리키는 단원 모두다. 다른 종류는 비어 있다.
    public var units: [UUID] { kind == .unit ? unitIds ?? id.map { [$0] } ?? [] : [] }
}
