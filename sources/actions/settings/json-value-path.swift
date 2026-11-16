import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension JSONValue {
    // 비어 있으면 파일에 쓰지 않는 항목(`review.dailyLimit`)도 있으므로, 선언된 항목이면 마지막 키를 새로 만든다.
    mutating func set(_ keys: [String], to value: JSONValue, path: String, adding: Bool = false) throws {
        guard let key = keys.first else { self = value; return }
        guard case .object(var o) = self, var child = o[key] ?? (adding && keys.count == 1 ? .null : nil) else {
            let known = if case .object(let o) = self { o.keys.sorted().joined(separator: ", ") } else { "" }
            throw ActionError.input(String(localized: .errorSettingsUnknownField(path, known)))
        }
        try child.set(Array(keys.dropFirst()), to: value, path: path, adding: adding)
        o[key] = child
        self = .object(o)
    }
}
