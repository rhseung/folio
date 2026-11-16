import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
@Query("backup list", "백업 목록, 새것부터", examples: ["folio backup list", "folio backup list --json"], phrases: ["백업 목록"])
public struct BackupList {
    public struct Row: Encodable {
        public var day: String
        public var path: String
    }

    public func read(_ ctx: ReadContext) throws -> [Row] {
        try ctx.backups().map { Row(day: $0.day.description, path: $0.url.path(percentEncoded: false)) }
    }
}
#endif
