import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialRole: ExpressibleByArgument {}
extension MaterialKind: ExpressibleByArgument {}

extension CourseRef {
    func local(_ ref: String) -> String {
        ref.hasPrefix(code + "/") ? String(ref.dropFirst(code.count + 1)) : ref
    }
}

func absolute(_ path: String) -> String {
    URL(filePath: (path as NSString).expandingTildeInPath, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath + "/"))
        .standardizedFileURL.path
}
