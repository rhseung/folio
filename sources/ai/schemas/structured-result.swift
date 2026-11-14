import FolioDomain
import Foundation

public protocol StructuredResult: Decodable, Sendable {
    static var schema: JSONValue { get }
}
