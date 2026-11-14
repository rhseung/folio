import FolioStorage
import Foundation

struct CLIError: Error {
    var exit: Exit
    var message: String
    var candidates: [String] = []
    var hints: [String] = []
}
