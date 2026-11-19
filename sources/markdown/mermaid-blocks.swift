import Markdown

// 미리보기가 mermaid로 그리는 코드 블록이다. 콜아웃이나 목록 안의 블록도 그리므로 문서 전체를 훑는다.
public enum MermaidBlocks {
    public static let language = "mermaid"

    public struct Block: Equatable, Sendable {
        // 파일의 첫 줄을 1로 센 여는 펜스의 줄이다.
        public let line: Int
        public let source: String
    }

    public static func find(in text: String) -> [Block] {
        let note = ParsedNote(text)
        let offset =
            text.split(separator: "\n", omittingEmptySubsequences: false).count
            - note.body.split(separator: "\n", omittingEmptySubsequences: false).count
        var found: [Block] = []
        func walk(_ node: Markup) {
            if let code = node as? CodeBlock {
                if code.language == language {
                    found.append(Block(line: (note.lines(of: code)?.lowerBound ?? 1) + offset, source: code.code))
                }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(note.document)
        return found
    }
}
