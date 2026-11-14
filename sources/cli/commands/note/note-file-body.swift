import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

struct NoteFileBody: Encodable {
    var name: String
    var path: String
    var text: String
    var hash: String
}
