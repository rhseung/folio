import FolioCore
import FolioDomain
import FolioStorage
import Foundation

// `hash`는 `note figure write`와 `note widget write`의 `--expect`에 넘길 값이다.
public struct NoteFileBody: Encodable {
    public var name: String
    public var path: String
    public var text: String
    public var hash: String

    init(name: String, path: String, text: String, hash: String? = nil) {
        (self.name, self.path, self.text, self.hash) = (name, path, text, hash ?? ContentHash.of(text))
    }
}
