import FolioDomain
import Foundation

extension ProblemArt: StoredModel {
    public static let schemaVersion = 1
}

extension CourseStore {
    var problemFiguresURL: URL { metadataURL.appending(path: StandardLayout.problemFiguresFolder) }

    // 문제나 지문의 ID로 찾는다. 읽지 못하는 파일은 건너뛴다. 그 항목은 다시 그리게 되고 새로 쓴 파일이 그것을 바꾼다.
    public func problemArt() -> [UUID: StoredDocument<ProblemArt>] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: problemFiguresURL, includingPropertiesForKeys: nil)
        else { return [:] }
        let docs = urls.filter { $0.pathExtension == "json" }.compactMap { try? StoredDocument<ProblemArt>.read(from: $0) }
        return Dictionary(docs.map { ($0.model.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func save(_ art: StoredDocument<ProblemArt>) throws {
        try FileManager.default.createDirectory(at: problemFiguresURL, withIntermediateDirectories: true)
        try art.write(to: fileURL(ProblemArt.path(art.model.id)))
    }
}
