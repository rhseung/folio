import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Query(
    "note figure show", "노트 그림의 SVG 원문. --json에는 note figure write --expect에 넘길 해시가 있다", phrases: ["그림 원문", "SVG 보기"],
    panel: true)
public struct NoteFigureShow {
    /// 과목
    @Arg public var course: Course.ID
    /// Notes/assets 안의 그림 이름. 예: graph.svg
    @Arg public var name: String

    public func read(_ ctx: ReadContext) throws -> NoteFileBody {
        let (file, text) = try MaterialText.figure(try ctx.store(course), name)
        // 쓸 때 넣은 스타일과 수식 모양을 걷어 낸, 쓴 사람이 쓴 모양을 보인다. 해시는 파일 그대로의 것이다. write가
        // 디스크의 파일과 견주기 때문이다.
        return NoteFileBody(name: file, path: NoteFigure.path(file), text: try NoteFigureFinish.source(text), hash: ContentHash.of(text))
    }
}
