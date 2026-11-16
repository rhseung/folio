import FolioDomain
import FolioStorage
import Foundation

// 노트 그림과 위젯 목록의 한 줄이다. `notes`는 원문에 그 파일 이름이 든 노트다.
public struct NoteFileItem: Encodable {
    public var name: String
    public var path: String
    public var size: Int
    public var modified: Date?
    public var notes: [String]

    static func list(_ store: CourseStore, _ files: [(name: String, path: String)]) -> [NoteFileItem] {
        let texts = ((try? store.notes()) ?? []).compactMap { n in
            (try? store.read(n)).map { (store.coursePath(of: n.url) ?? n.url.lastPathComponent, $0) }
        }
        return files.map { f in
            let values = try? store.fileURL(f.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return NoteFileItem(
                name: f.name, path: f.path, size: values?.fileSize ?? 0, modified: values?.contentModificationDate,
                notes: texts.filter { $0.1.contains(f.name) }.map(\.0))
        }
    }
}
