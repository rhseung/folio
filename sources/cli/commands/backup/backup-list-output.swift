import FolioActions
import FolioDomain
import Foundation

extension BackupList: QueryOutput {
    func say(_ rows: [Row], _ r: Resolver) throws {
        var t = Table(header: [String(localized: .backupListHeaderDate), String(localized: .backupListHeaderFile)], shrink: [1])
        for a in rows { t.rows.append([a.day, a.path.link(URL(filePath: a.path))]) }
        t.print()
        footer(rows.count)
    }
}
