import Foundation

public enum Term: String, CaseIterable, Codable, Sendable {
    case spring, summer, fall, winter
    case credited

    public var folderNumber: Int? {
        switch self {
        case .spring: 1
        case .summer: 2
        case .fall: 3
        case .winter: 4
        case .credited: nil
        }
    }
}
