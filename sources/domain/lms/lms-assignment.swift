import Foundation

public struct LMSAssignment: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var classroom: Int
    public var title: String
    public var due: Date?
    public var submitted: Bool
    // 과제 목록 표에는 첨부가 없어 과제 페이지를 따로 읽어야 한다. 읽지 않았으면 nil이다.
    public var attachments: [LMSAttachment]?

    public init(
        id: Int, classroom: Int, title: String, due: Date? = nil, submitted: Bool = false, attachments: [LMSAttachment]? = nil
    ) {
        self.id = id
        self.classroom = classroom
        self.title = title
        self.due = due
        self.submitted = submitted
        self.attachments = attachments
    }

    public var key: LMSKey { .init(kind: .assignment, id: id) }
    public var url: URL { LMS.url("/mod/assign/view.php?id=\(id)") }
}
