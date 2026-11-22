import Foundation

public enum ReadinessState: String, Sendable, CaseIterable {
    case ready
    case weak
    // 판정이 하나도 없다.
    case noVerdict
    // 단원에 이은 문제가 최소 개수보다 적다.
    case fewProblems
}

extension ReadinessState {
    public var label: String {
        switch self {
        case .ready: String(localized: .readinessReady)
        case .weak: String(localized: .readinessWeak)
        case .noVerdict: String(localized: .readinessNoVerdict)
        case .fewProblems: String(localized: .readinessFewProblems)
        }
    }
}
