import FolioDomain
import Foundation

extension JSONValue {
    /// Returns `new` plus every key of `old` that `model` (the value `new` was encoded from) has no property for,
    /// recursing into nested objects and into arrays matched by `id`. Fields written by a newer app version
    /// survive a save this way, while fields the model knows and cleared stay cleared.
    static func preservingUnknownKeys(old: JSONValue, new: JSONValue, model: Any) -> JSONValue {
        let mirror = Mirror(reflecting: unwrapped(model))
        switch (old, new, mirror.displayStyle) {
        case (_, _, .dictionary):
            return new  // dictionary keys are data, not fields: a missing key was deleted
        case (.object(let o), .object(var n), _):
            let properties = Dictionary(
                mirror.children.compactMap { c in c.label.map { ($0, c.value) } },
                uniquingKeysWith: { a, _ in a }
            )
            for (key, oldValue) in o {
                if let newValue = n[key], let child = properties[key] {
                    n[key] = preservingUnknownKeys(old: oldValue, new: newValue, model: child)
                } else if properties[key] == nil {
                    n[key] = oldValue
                }
            }
            return .object(n)
        case (.array(let o), .array(let n), _):
            let elements = Array(mirror.children.map(\.value))
            guard elements.count == n.count else { return new }
            let oldByID = Dictionary(o.compactMap { v in v["id"].map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
            return .array(zip(n, elements).map { newElement, model in
                guard let id = newElement["id"], let oldElement = oldByID[id] else { return newElement }
                return preservingUnknownKeys(old: oldElement, new: newElement, model: model)
            })
        default:
            return new
        }
    }

    private static func unwrapped(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional, let wrapped = mirror.children.first?.value else { return value }
        return unwrapped(wrapped)
    }
}

/// The one JSON format for every Folio file: sorted keys and pretty printing keep iCloud and git diffs small,
/// and fractional-second ISO 8601 dates keep event order stable within a second.
enum JSONFormat {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(dateStyle))
        }
        return e
    }()

    static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = encoder.dateEncodingStrategy
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? dateStyle.parse(string) { return date }
            return try Date.ISO8601FormatStyle().parse(string)
        }
        return d
    }()

    static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

extension JSONDecoder {
    public static var folio: JSONDecoder { JSONFormat.decoder }
}

extension JSONEncoder {
    /// The encoder Folio writes its files with, so CLI output reads like course.json.
    public static var folio: JSONEncoder { JSONFormat.encoder }
}
