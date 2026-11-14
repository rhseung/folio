import FolioStorage
import Foundation

// MARK: Style

enum Style {
    case bold, dim, green, yellow, red, blue, magenta, cyan

    static let isTerminal = isatty(STDOUT_FILENO) == 1
    static let enabled = isTerminal && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    var sgr: String {
        switch self {
        case .bold: "1"
        case .dim: "2"
        case .green: "32"
        case .yellow: "33"
        case .red: "31"
        case .blue: "34"
        case .magenta: "35"
        case .cyan: "36"
        }
    }
}
