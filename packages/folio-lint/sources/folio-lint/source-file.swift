import Foundation
import SwiftParser
import SwiftSyntax

public struct SourceFile {
    public let path: String
    public let tree: SourceFileSyntax
    let lines: [Substring]
    // UTF-8 offsets, as swift-syntax positions are.
    private let lineStarts: [Int]

    init(path: String, text: String) {
        self.path = path
        tree = Parser.parse(source: text)
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var starts = [0]
        for (offset, byte) in text.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            starts.append(offset + 1)
        }
        lineStarts = starts
    }

    func line(of position: AbsolutePosition) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= position.utf8Offset { low = middle + 1 } else { high = middle }
        }
        return low
    }

    func line(of node: some SyntaxProtocol) -> Int { line(of: node.positionAfterSkippingLeadingTrivia) }

    func lineStart(_ line: Int) -> Int { lineStarts[line - 1] }

    func nodes<Node: SyntaxProtocol>(_ type: Node.Type) -> [Node] {
        var found: [Node] = []
        walk(Syntax(tree)) { if let node = $0.as(Node.self) { found.append(node) } }
        return found
    }

    var tokens: TokenSequence { tree.tokens(viewMode: .sourceAccurate) }
}

func walk(_ node: Syntax, _ visit: (Syntax) -> Void) {
    visit(node)
    for child in node.children(viewMode: .sourceAccurate) {
        walk(child, visit)
    }
}

/// The repository's Swift files by path from its root, each parsed once however many rules read it.
public final class Codebase {
    private let texts: [String: String]
    private var parsed: [String: SourceFile] = [:]

    public init(files: [String: String]) {
        texts = files
    }

    public convenience init(root: String) throws {
        var files: [String: String] = [:]
        for folder in ["app", "packages"] {
            let base = (root as NSString).appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(atPath: base) else { continue }
            while let path = walker.nextObject() as? String {
                // Hidden folders hold build products (`.build`) and editor state, never sources.
                if (path as NSString).lastPathComponent.hasPrefix(".") {
                    walker.skipDescendants()
                    continue
                }
                guard path.hasSuffix(".swift") else { continue }
                files[folder + "/" + path] = try String(contentsOfFile: base + "/" + path, encoding: .utf8)
            }
        }
        self.init(files: files)
    }

    func files(under folders: String...) -> [SourceFile] {
        texts.keys.filter { path in folders.contains { path.hasPrefix($0 + "/") } }.sorted().map(file)
    }

    private func file(_ path: String) -> SourceFile {
        if let file = parsed[path] { return file }
        let file = SourceFile(path: path, text: texts[path] ?? "")
        parsed[path] = file
        return file
    }
}
