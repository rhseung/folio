import FolioDomain
import FolioStorage
import Foundation

public struct LMSAcceptItem: Codable, Sendable, Hashable {
    public var key: String
    public var title: String?
    public var due: Date?
    public var file: String?
    public var files: [String]?

    public init(key: String, title: String? = nil, due: Date? = nil, file: String? = nil, files: [String]? = nil) {
        (self.key, self.title, self.due, self.file, self.files) = (key, title, due, file, files)
    }
}
