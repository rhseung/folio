import Foundation

public enum ModelError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case rule(String)
    public var description: String {
        switch self {
        case .notFound(let s), .rule(let s): s
        }
    }
}
