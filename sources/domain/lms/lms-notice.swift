import Foundation

public struct LMSNotice: Codable, Hashable, Sendable, Identifiable {
    // `bwid`는 게시판 전체에서 겹치지 않는다.
    public var id: Int
    public var board: Int
    public var classroom: Int
    public var title: String
    public var author: String?
    public var posted: Date?

    public init(id: Int, board: Int, classroom: Int, title: String, author: String? = nil, posted: Date? = nil) {
        self.id = id
        self.board = board
        self.classroom = classroom
        self.title = title
        self.author = author
        self.posted = posted
    }

    public var key: LMSKey { .init(kind: .notice, id: id) }
    public var url: URL { LMS.url("/mod/ubboard/article.php?id=\(board)&bwid=\(id)") }
}
