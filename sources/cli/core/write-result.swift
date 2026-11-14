import FolioActions
import FolioDomain
import Foundation

struct WriteResult: Encodable {
    var action: String
    var dryRun: Bool
    var made: UUID?
    var changes: [Change]
    var notes: [String]
    var read: JSONValue?
}
