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

    init(_ e: ModelError) {
        switch e {
        case .notFound(let s): self = .notFound(s)
        case .rule(let s): self = .rule(s)
        }
    }
}
