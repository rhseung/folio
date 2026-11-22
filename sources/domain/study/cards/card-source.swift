import Foundation

public enum CardSource: String, Codable, Sendable, CaseIterable {
    case manual, note, claude
}
