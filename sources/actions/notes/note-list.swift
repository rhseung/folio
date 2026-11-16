import FolioDomain
import FolioStorage
import Foundation

@Query(
    "note list", "과목의 노트 목록", examples: ["folio note list EC4207", "folio note list EC4207 --lines"], phrases: ["노트 목록"],
    panel: true, lines: true)
public struct NoteList {
    /// 과목
    @Arg public var course: Course.ID

    public struct Item: Encodable {
        public var id: UUID?
        public var path: String
        public var kind: NoteKind
        public var sessionId: UUID?
        public var sessionIds: [UUID]
        public var examId: UUID?
        public var unitIds: [UUID]
        // 화면과 명령줄에 쓰는 이름이다. JSON에는 없다.
        public var title: String
    }

    public func read(_ ctx: ReadContext) throws -> [Item] {
        let store = try ctx.store(course)
        return try store.notes().map { n in
            Item(
                id: n.meta.id, path: store.coursePath(of: n.url) ?? n.url.lastPathComponent, kind: n.meta.kind, sessionId: n.meta.sessionId,
                sessionIds: n.meta.sessionIds, examId: n.meta.examId, unitIds: n.meta.unitIds, title: n.title)
        }
    }
}

extension NoteList.Item {
    private enum CodingKeys: String, CodingKey { case id, path, kind, sessionId, sessionIds, examId, unitIds }
}
