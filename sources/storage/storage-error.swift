import FolioDomain
import Foundation

public enum StorageError: Error, Equatable {
    case missingSchemaVersion(URL)
    case missingMigration(from: Int, URL)
    case newerSchema(found: Int, supported: Int, URL)
    case coordination(String)
    // 다른 인코딩의 글 파일(CP949 `.csv`)을 느슨하게 읽어 다시 저장하면 디코딩하지 못한 바이트를 모두 잃으므로, 아예
    // 읽지 않는다.
    case notUTF8(String)
    case outsideStage(String)
}
