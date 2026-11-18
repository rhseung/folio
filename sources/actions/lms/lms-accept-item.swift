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
    // 과제를 받을 때 LMS 과제 페이지에 있던 첨부 수다. 뷰어 전용이라 내려받지 못한 첨부가 다음 동기화에서 새 첨부로 다시
    // 제안되지 않도록, 받으면서 이 수의 새 첨부 키(`attachments:<과제>:<수>`)를 함께 숨긴다.
    public var attachmentCount: Int?

    public init(
        key: String, classroom: Int? = nil, title: String? = nil, due: Date? = nil, file: String? = nil, files: [String]? = nil,
        attachmentCount: Int? = nil
    ) {
        (self.key, self.classroom, self.title, self.due, self.file, self.files) = (key, classroom, title, due, file, files)
        self.attachmentCount = attachmentCount
    }
}
