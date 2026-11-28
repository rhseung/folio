import Foundation

public struct ExamPlanTarget: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        // 정리 노트의 한 단계다. `id`는 노트이고 `stage`가 단계다.
        case note
        // 정리 노트가 없는 범위 단원에 노트를 만드는 일이다. `id`는 단원이다.
        case makeNote = "make_note"
        case mock
        // 사용자가 쓴 할 일이다.
        case custom
    }

    public var kind: Kind
    public var id: UUID?
    public var stage: PlanStage?

    public init(kind: Kind, id: UUID? = nil, stage: PlanStage? = nil) {
        self.kind = kind
        self.id = id
        self.stage = stage
    }

    public static func note(_ id: UUID, _ stage: PlanStage) -> ExamPlanTarget { ExamPlanTarget(kind: .note, id: id, stage: stage) }
    public static func makeNote(_ unit: UUID) -> ExamPlanTarget { ExamPlanTarget(kind: .makeNote, id: unit) }
    public static let mock = ExamPlanTarget(kind: .mock)
    public static let custom = ExamPlanTarget(kind: .custom)
}
