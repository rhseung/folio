import Foundation

public enum StreamEvent: Sendable, Equatable {
    case turn
    case text(String)
    case tool(String)
    case toolInput(String)
}
