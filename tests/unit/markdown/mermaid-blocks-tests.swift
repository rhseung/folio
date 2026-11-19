import FolioMarkdown
import Testing

struct MermaidBlocksTests {
    @Test func blocksAreFoundWithTheirFileLines() {
        let text =
            "---\ntags: [a]\n---\n# 제목\n\n> [!note]\n> ```mermaid\n> flowchart LR\n>   A --> B\n> ```\n\n```mermaid\nflowchart TD\n  C --> D\n```\n"
        #expect(MermaidBlocks.find(in: text).map(\.line) == [7, 12])
        #expect(MermaidBlocks.find(in: text).last?.source == "flowchart TD\n  C --> D\n")
    }
}
