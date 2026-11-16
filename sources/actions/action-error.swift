import FolioDomain
import FolioStorage
import Foundation

public enum ActionError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case rule(String)
    case conflict(String)
    case input(String)

    public var description: String {
        switch self {
        case .notFound(let s), .rule(let s), .conflict(let s), .input(let s): s
        }
    }

    // 다른 기기가 먼저 적용한 제안이다. 부르는 쪽은 실패가 아니라 적용된 것으로 본다.
    public static var applied: ActionError { .conflict(String(localized: .errorProposalApplied)) }

    init(_ e: ModelError) {
        switch e {
        case .notFound(let s): self = .notFound(s)
        case .rule(let s): self = .rule(s)
        }
    }
}
