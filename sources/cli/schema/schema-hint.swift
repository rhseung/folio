import FolioActions
import FolioDomain
import FolioStorage
import Foundation

protocol SchemaHint {
    static var schema: JSONValue { get }
    static var example: Any { get }
}
