import FolioDomain
import FolioStorage
import Foundation

public struct LMSAcceptItem: Codable, Sendable, Hashable {
    public var key: String
    // 항목이 올라온 LMS 강의실이다. 과목을 주면 그 과목을 이 강의실에 기억하고, 주지 않으면 기억한 과목에 넣는다.
    public var classroom: Int?
    public var title: String?
    public var due: Date?
    public var file: String?
    public var files: [String]?

    public init(
        key: String, classroom: Int? = nil, title: String? = nil, due: Date? = nil, file: String? = nil, files: [String]? = nil
    ) {
        (self.key, self.classroom, self.title, self.due, self.file, self.files) = (key, classroom, title, due, file, files)
    }
}
