import Foundation

// 판정이 무엇을 기준으로 났는지다. Claude가 해설 없이 자기 풀이로 채점한 판정은 준비 계산에서 무게가 절반이다.
public enum GradeBasis: String, Codable, Sendable, CaseIterable {
    case key
    case solution
    case claude
    case user

    public var weight: Double { self == .claude ? 0.5 : 1 }
}
