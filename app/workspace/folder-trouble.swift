import FolioDomain
import FolioStorage
import Foundation

enum FolderTrouble: Equatable {
    case missing(path: String)
    case downloading(path: String, done: Int, total: Int)

    var path: String {
        switch self {
        case .missing(let path), .downloading(let path, _, _): path
        }
    }
}
