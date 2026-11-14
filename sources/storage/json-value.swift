import FolioDomain
import Foundation

extension JSONValue {
    static func preservingUnknownKeys(old: JSONValue, new: JSONValue, model: Any) -> JSONValue {
        let mirror = Mirror(reflecting: unwrapped(model))
        switch (old, new, mirror.displayStyle) {
        case (_, _, .dictionary):
            // 딕셔너리 키는 필드가 아니라 데이터이므로, 빠진 키는 지운 것이다.
            return new
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
            return .array(
                zip(n, elements).map { newElement, model in
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

extension JSONDecoder {
    public static var folio: JSONDecoder { JSONFormat.decoder }
}

extension JSONEncoder {
    public static var folio: JSONEncoder { JSONFormat.encoder }
}
