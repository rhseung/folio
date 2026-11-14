import Foundation

public enum MaterialStatus: String, Codable, Sendable, CaseIterable {
    case classified, unclassified, missing, ignored
}
