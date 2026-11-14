import FolioDomain
import FolioStorage
import Foundation

extension JSONValue {
    mutating func set(_ keys: [String], to value: JSONValue, path: String) throws {
        guard let key = keys.first else { self = value; return }
        guard case .object(var o) = self, var child = o[key] else {
            let known = if case .object(let o) = self { o.keys.sorted().joined(separator: ", ") } else { "" }
            throw ActionError.input(String(localized: .errorSettingsUnknownField(path, known)))
        }
        try child.set(Array(keys.dropFirst()), to: value, path: path)
        o[key] = child
        self = .object(o)
    }
}
