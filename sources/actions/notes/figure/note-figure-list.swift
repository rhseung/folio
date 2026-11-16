import FolioDomain
import FolioStorage
import Foundation

@Query(
    "note figure list", "과목의 노트 그림과 그 그림을 쓰는 노트", phrases: ["그림 목록", "SVG 목록"], panel: true)
public struct NoteFigureList {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [NoteFileItem] {
        let store = try ctx.store(course)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.fileURL(NoteFigure.folder).path)) ?? []
        let files = names.filter { $0.lowercased().hasSuffix(".svg") }.sorted()
        return NoteFileItem.list(store, files.map { ($0, NoteFigure.path($0)) })
    }
}
