import Foundation

// 정리 노트 하나를 끝내는 차례다. 정리를 외우고 이해해야 문제에 쓸 수 있어서 증명이 문제풀이보다 앞이다.
public enum PlanStage: String, Codable, Sendable, CaseIterable, Comparable {
    case read, proof, solve

    public static func < (a: Self, b: Self) -> Bool { a.order < b.order }

    var order: Int {
        switch self {
        case .read: 0
        case .proof: 1
        case .solve: 2
        }
    }

    // 증명은 정리류 블록이 있는 노트에만 있는 단계다.
    public static func stages(proof: Bool) -> [PlanStage] { proof ? allCases : [.read, .solve] }

    public var label: String {
        switch self {
        case .read: String(localized: .planStageRead)
        case .proof: String(localized: .planStageProof)
        case .solve: String(localized: .planStageSolve)
        }
    }
}
