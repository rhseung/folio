import ArgumentParser
import FolioDomain
import Foundation

struct Toggle: ExpressibleByArgument {
    var value: Bool
    init?(argument: String) {
        switch argument.lowercased() {
        case "true", "yes", "on", "1", "켜기", "예": value = true
        case "false", "no", "off", "0", "끄기", "아니오": value = false
        default: return nil
        }
    }
    static var allValueStrings: [String] { ["true", "false"] }
}
