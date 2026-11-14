import Foundation
import SwiftParser
import SwiftSyntax

public struct SourceFile {
    public let path: String
    public let tree: SourceFileSyntax
    let lines: [Substring]
    // swift-syntax의 위치처럼 UTF-8 offset이다.
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
