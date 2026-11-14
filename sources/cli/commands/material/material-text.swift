import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

enum MaterialText {
    static func read(_ store: CourseStore, _ path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw CLIError(exit: .notFound, message: String(localized: .noteFileMissing(path)))
        }
        do {
            return try store.readText(path)
        } catch StorageError.notUTF8 {
            throw CLIError(exit: .rule, message: String(localized: .noteFileNotUtf8(path)))
        }
    }
}
