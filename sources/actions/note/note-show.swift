import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Query(
    "note show", "노트 파일을 그대로 출력",
    examples: ["folio note show EC4207/09-08", "folio note show \"EC4207/Notes/09-08(화) 매칭.md\""], phrases: ["노트 보기", "노트 읽기"],
    panel: true)
public struct NoteShow {
    @Arg public var course: Course.ID
    /// 노트 제목 또는 경로
    @Arg public var note: Note.Path

    public struct Body: Encodable {
        public var id: UUID?
        public var path: String
        public var text: String
        public var hash: String
    }

    public func read(_ ctx: ReadContext) throws -> Body {
        let n = try ctx.note(course, path: note)
        let text = try ctx.store(course).read(n)
        return Body(id: n.meta.id, path: note, text: text, hash: ContentHash.of(text))
    }
}
