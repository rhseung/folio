import Foundation

public struct ProposalTarget: Sendable, Equatable {
    public enum Effect: Sendable, Equatable {
        case replaces(covers: Set<String>)
        case sets
    }

    public var arguments: [String]
    public var effect: Effect

    public init(arguments: [String], effect: Effect) {
        self.arguments = arguments
        self.effect = effect
    }

    public func overrides(_ earlier: ActionProposal, with later: ActionProposal) -> Bool {
        guard let item = later.target(arguments), earlier.target(arguments) == item else { return false }
        switch effect {
        case .replaces(let covers):
            return earlier.command == later.command || covers.contains(earlier.command)
        case .sets:
            // 입력에 없는 필드는 그대로 남는다(`Patch.keep`, nil인 옵셔널). `null`은 값을 지우므로 바꾼 필드로 센다.
            func fields(_ p: ActionProposal) -> Set<String> {
                guard case .object(let o) = p.input else { return [] }
                return Set(o.keys).subtracting(arguments)
            }
            return earlier.command == later.command && fields(earlier).isSubset(of: fields(later))
        }
    }
}
