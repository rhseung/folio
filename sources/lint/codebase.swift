import Foundation
import SwiftParser
import SwiftSyntax

public final class Codebase {
    private let texts: [String: String]
    private var parsed: [String: SourceFile] = [:]

    public init(files: [String: String]) {
        texts = files
    }

    public convenience init(root: String) throws {
        var files: [String: String] = [:]
        for folder in ["sources", "tests"] {
            let base = (root as NSString).appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(atPath: base) else { continue }
            while let path = walker.nextObject() as? String {
                let name = (path as NSString).lastPathComponent
                if name.hasPrefix(".") || name == "node_modules" {
                    walker.skipDescendants()
                    continue
                }
                guard path.hasSuffix(".swift") else { continue }
                files[folder + "/" + path] = try String(contentsOfFile: base + "/" + path, encoding: .utf8)
            }
        }
        self.init(files: files)
    }

    var paths: [String] { texts.keys.sorted() }

    func files(under folders: String..., except skipped: String...) -> [SourceFile] {
        texts.keys.filter { path in
            folders.contains { path.hasPrefix($0 + "/") } && !skipped.contains { path.hasPrefix($0 + "/") }
        }.sorted().map(file)
    }

    private func file(_ path: String) -> SourceFile {
        if let file = parsed[path] { return file }
        let file = SourceFile(path: path, text: texts[path] ?? "")
        parsed[path] = file
        return file
    }
}
