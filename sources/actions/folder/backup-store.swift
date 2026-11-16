import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
extension ActionContext {
    func backupStore() throws -> BackupStore {
        BackupStore(
            gist: gist, folder: URL(filePath: (try settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory))
    }
}
#endif
