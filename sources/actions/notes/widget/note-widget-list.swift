import FolioDomain
import FolioStorage
import Foundation

@Query("note widget list", "과목의 위젯과 그 위젯을 쓰는 노트", phrases: ["위젯 목록"], panel: true)
public struct NoteWidgetList {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [NoteFileItem] {
        let store = try ctx.store(course)
        let folder = StandardLayout.metadataFolder + "/" + StandardLayout.widgetsFolder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.fileURL(folder).path)) ?? []
        let ids = names.compactMap { n in n.hasSuffix(".html") ? UUID(uuidString: String(n.dropLast(5))) : nil }
            .sorted { $0.uuidString < $1.uuidString }
        return NoteFileItem.list(store, ids.map { ($0.uuidString, NoteWidget.path($0)) }) { path in
            (try? MaterialText.read(store, path)).flatMap(NoteWidget.title)
        }
    }
}
