import Foundation

public enum ReadinessState: String, Sendable, CaseIterable {
    case ready
    case weak
    // 판정이 하나도 없다.
    case noVerdict
    // 단원에 이은 문제가 최소 개수보다 적다.
    case fewProblems
    // 문제는 넉넉하지만 판정받은 문제가 최소 개수보다 적다. 안 푼 문제가 점수 0으로 들어가 약함으로 보이지 않게 따로 둔다.
    case fewVerdicts
}

extension ReadinessState {
    public var label: String {
        switch self {
        case .ready: String(localized: .readinessReady)
        case .weak: String(localized: .readinessWeak)
        case .noVerdict: String(localized: .readinessNoVerdict)
        case .fewProblems: String(localized: .readinessFewProblems)
        case .fewVerdicts: String(localized: .readinessFewVerdicts)
        }
    }
}
