import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    func notePath(_ ref: String) throws -> (CourseRef, NoteFile, String) {
        let (c, name) = try split(ref)
        let n = try note(name, in: c)
        return (c, n, c.store.coursePath(of: n.url) ?? name)
    }
}

func contentHash(_ text: String) -> String { ContentHash.of(text) }

func readText(_ source: String) throws -> String {
    if source == "-" { return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
    do {
        return try String(contentsOf: URL(filePath: absolute(source)), encoding: .utf8)
    } catch {
        throw CLIError(exit: .usage, message: String(localized: .noteReadFailed(source)))
    }
}
