import FolioDomain
import FolioStorage
import Foundation

// 노트 그림과 위젯 목록의 한 줄이다. `notes`는 원문에 그 파일 이름이 든 노트다. `title`은 위젯 HTML의 `<title>`이다.
public struct NoteFileItem: Encodable {
    public var name: String
    public var title: String?
    public var path: String
    public var size: Int
    public var modified: Date?
    public var notes: [String]

    static func list(
        _ store: CourseStore, _ files: [(name: String, path: String)], title: (String) -> String? = { _ in nil }
    ) -> [NoteFileItem] {
        let texts = ((try? store.notes()) ?? []).compactMap { n in
            (try? store.read(n)).map { (store.coursePath(of: n.url) ?? n.url.lastPathComponent, $0) }
        }
        return files.map { f in
            let values = try? store.fileURL(f.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return NoteFileItem(
                name: f.name, title: title(f.path), path: f.path, size: values?.fileSize ?? 0, modified: values?.contentModificationDate,
                notes: texts.filter { $0.1.contains(f.name) }.map(\.0))
        }
    }
}
