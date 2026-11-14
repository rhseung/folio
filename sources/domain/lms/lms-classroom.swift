import Foundation

public struct LMSClassroom: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var kind: String?
    public var professors: String?

    public init(id: Int, title: String, kind: String? = nil, professors: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.professors = professors
    }

    public var url: URL { LMS.url("/course/view.php?id=\(id)") }
}
