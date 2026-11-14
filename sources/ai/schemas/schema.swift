import FolioDomain
import Foundation

enum Schema {
    static func object(_ properties: [String: JSONValue], required: [String]? = nil) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array((required ?? properties.keys.sorted()).map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }
    static let string: JSONValue = .object(["type": .string("string")])
    static let integer: JSONValue = .object(["type": .string("integer")])
    static let number: JSONValue = .object(["type": .string("number")])
    static let boolean: JSONValue = .object(["type": .string("boolean")])
    static func enumeration(_ values: [String]) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))])
    }
    static func array(_ item: JSONValue) -> JSONValue { .object(["type": .string("array"), "items": item]) }
    static func nullable(_ t: JSONValue) -> JSONValue { .object(["anyOf": .array([t, .object(["type": .string("null")])])]) }
}
