import Foundation
import Markdown

// 노트 카드에 보이는 본문 앞부분이다. frontmatter와 제목, 코드, 수식 블록, 표를 빼고 문단과 목록의 글만 이어 붙인다.
public enum NoteExcerpt {
    public static func text(of source: String, tex: Bool = false, limit: Int = 240) -> String {
        let words = tex ? texWords(source) : markdownWords(Frontmatter.split(source).body)
        var result = ""
        for word in words {
            let line = tidy(word)
            guard !line.isEmpty else { continue }
            result += result.isEmpty ? line : " " + line
            if result.count >= limit { break }
        }
        return String(result.prefix(limit))
    }

    static func markdownWords(_ body: String) -> [String] {
        var lines: [String] = []
        func walk(_ markup: any Markup) {
            switch markup {
            case is Heading, is CodeBlock, is HTMLBlock, is Table, is ThematicBreak: return
            case let paragraph as Paragraph:
                lines.append(paragraph.children.map(plain).joined())
            default:
                for child in markup.children { walk(child) }
            }
        }
        walk(Document(parsing: body))
        return lines
    }

    // 위키 링크와 수식은 swift-markdown이 모르는 문법이라 글 그대로 남고, `tidy`가 정리한다.
    static func plain(_ inline: any Markup) -> String {
        switch inline {
        case let text as Markdown.Text: text.string
        case is SoftBreak, is LineBreak: " "
        case let code as InlineCode: code.code
        case is Markdown.Image, is InlineHTML: ""
        default: inline.children.map(plain).joined()
        }
    }

    static func texWords(_ source: String) -> [String] {
        let body = source.range(of: "\\begin{document}").map { String(source[$0.upperBound...]) } ?? source
        return body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let kept = line.firstIndex(of: "%").map { line[..<$0] } ?? line[...]
            let trimmed = kept.trimmingCharacters(in: .whitespaces)
            // 명령만 있는 줄(`\section{…}`, `\begin{proof}`)은 본문이 아니다.
            return trimmed.hasPrefix("\\") ? "" : trimmed
        }
    }

    static func tidy(_ line: String) -> String {
        var s = line
        s.replace(/!\[\[[^\]]*\]\]/, with: "")
        s.replace(/\[\[([^\]|]*)\|([^\]]*)\]\]/) { String($0.output.2) }
        s.replace(/\[\[([^\]#]*)[^\]]*\]\]/) { String($0.output.1) }
        s.replace(/^\[![A-Za-z-]+\][+-]?\s*/, with: "")
        s.replace(/\s\^[A-Za-z0-9-]+$/, with: "")
        s.replace(/\s+/, with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }
}
