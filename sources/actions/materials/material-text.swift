import FolioDomain
import FolioStorage
import Foundation

public enum MaterialText {
    public static func read(_ store: CourseStore, _ path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.notFound(String(localized: .errorFileMissing(path)))
        }
        do {
            return try store.readText(path)
        } catch StorageError.notUTF8 {
            throw ActionError.rule(String(localized: .errorFileNotUtf8(path)))
        }
    }

    // 읽기에서 틀린 그림 이름은 사용법 오류(종료 코드 2)다. 쓰기(`NoteFigureAdd.fileName`)는 규칙 오류로 알린다.
    public static func figure(_ store: CourseStore, _ name: String) throws -> (file: String, text: String) {
        guard let file = NoteFigure.fileName(name) else { throw ActionError.input(String(localized: .errorFigureName(name))) }
        return (file, try read(store, NoteFigure.path(file)))
    }
}
