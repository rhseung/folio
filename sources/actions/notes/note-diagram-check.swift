import FolioDomain
import FolioMarkdown

// 노트 본문의 mermaid 도식을 쓰기 전에 그림처럼 검사한다. 도식은 미리보기에서야 그려지므로, 미리보기를 보지 못하고 쓰는
// 쪽(Claude, CLI)은 라벨이 도형 밖으로 넘쳐도 알 수 없다.
enum NoteDiagramCheck {
    // `before`에 같은 원문으로 있던 블록은 보지 않는다. 이미 깨진 도식이 노트의 다른 곳을 고치는 쓰기까지 막지 않게 한다.
    static func check(_ text: String, format: NoteFormat, before: String? = nil) throws {
        guard format == .markdown else { return }
        let kept = Set(before.map { MermaidBlocks.find(in: $0).map(\.source) } ?? [])
        var lines: [String] = []
        for (i, block) in MermaidBlocks.find(in: text).enumerated() where !kept.contains(block.source) {
            for p in try NoteFigureFinish.diagramProblems(block.source) {
                lines.append(String(localized: .errorNoteDiagram(i + 1, block.line, p.message)))
            }
        }
        guard !lines.isEmpty else { return }
        throw ActionError.rule((lines + [String(localized: .errorNoteDiagramHint)]).joined(separator: "\n"))
    }
}
