import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

struct NoteFileItem: Encodable {
    var name: String
    var path: String
    var size: Int
    var modified: Date?
    var notes: [String]
}
