import Foundation

public enum OnDelete: Sendable {
    case cascade
    case nullify
    case restrict
    case reparent
}
