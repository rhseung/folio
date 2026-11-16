import Foundation

public enum FileRenderer: Equatable, Sendable {
    case pdf
    case markdown
    case source
    case image
    case audio
    case quickLook
}
