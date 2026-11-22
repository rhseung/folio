import Foundation
import Markdown

// 노트의 콜아웃 하나로 만드는 카드의 앞뒤다(#579 "노트 블록에서 만들기"). 앞은 콜아웃의 제목, 뒤는 본문이다. 카드는 블록 ID로
// 원본을 다시 찾으므로, ID가 없는 블록에는 마지막 줄에 ID를 달아야 한다(`tag`).
public struct NoteBlockCard: Equatable, Sendable {
    public var type: String
    public var front: String
    public var back: String
    public var blockID: String?
    // 본문 기준 줄 번호(1부터)다.
    public var lines: ClosedRange<Int>

    // `line`은 콜아웃의 첫 줄이다. 미리보기는 콜아웃에 이 줄을 단다.
    public static func at(line: Int, in text: String, callouts: CalloutTable = .standard) -> NoteBlockCard? {
        let note = ParsedNote(text)
        guard
            let quote = note.document.children.compactMap({ $0 as? BlockQuote }).first(where: { note.lines(of: $0)?.lowerBound == line }),
            let header = quote.calloutHeader, callouts[header.type]?.makesCard ?? false, let lines = note.lines(of: quote)
        else { return nil }
        let rows = note.bodyLines[(lines.lowerBound - 1)...(lines.upperBound - 1)].map { row in
            let quoted = row.drop { $0 == " " }
            guard quoted.hasPrefix(">") else { return String(quoted) }
            let rest = quoted.dropFirst()
            return String(rest.hasPrefix(" ") ? rest.dropFirst() : rest)
        }
        var body = Array(rows.dropFirst())
        var id: String?
        if let last = body.indices.last {
            let (rest, found) = BlockID.strip(body[last])
            body[last] = rest
            id = found
        }
        let back = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = header.title.trimmingCharacters(in: .whitespaces)
        let front = title.isEmpty ? header.type.prefix(1).uppercased() + header.type.dropFirst() : title
        guard !back.isEmpty else { return nil }
        return NoteBlockCard(type: header.type, front: front, back: back, blockID: id, lines: lines)
    }

    // 카드가 기억하는 블록 ID로 콜아웃을 다시 찾는다. 원본에 맞춰 카드를 고칠 때 쓴다.
    public static func find(_ id: String, in text: String, callouts: CalloutTable = .standard) -> NoteBlockCard? {
        let note = ParsedNote(text)
        guard let (top, _) = note.blockLines(id) else { return nil }
        return at(line: top.lowerBound, in: text, callouts: callouts)
    }

    // ID를 달 마지막 줄의 새 글이다. 줄 번호는 frontmatter를 포함한 글 전체 기준이다. 이미 ID가 있으면 nil이다.
    public struct Tag: Equatable, Sendable {
        public let line: Int
        public let old: String
        public let new: String
    }

    public func tagged(_ text: String, id: String) -> Tag? {
        guard blockID == nil else { return nil }
        let note = ParsedNote(text)
        let line = lines.upperBound
        guard line <= note.bodyLines.count else { return nil }
        let offset = text.split(separator: "\n", omittingEmptySubsequences: false).count - note.bodyLines.count
        let old = String(note.bodyLines[line - 1])
        let kept = old.replacing(/[ \t]+$/, with: "")
        return Tag(line: line + offset, old: old, new: kept + " ^" + id)
    }

    // 카드가 기억하는 원본 블록의 글이다. 블록을 지웠거나 ID가 없어졌으면 nil이다.
    public static func source(of id: String, in text: String) -> String? {
        ParsedNote(text).blockSource(id)
    }
}
