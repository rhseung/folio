import Foundation

extension ParsedNote {
    public func line(heading: String?, block: String?) -> Int? {
        if let block {
            guard let (top, item) = blockLines(block) else { return nil }
            return (item ?? top).lowerBound
        }
        guard let heading else { return nil }
        let tops = Array(document.children)
        return headingIndex(heading, in: tops).flatMap { lines(of: tops[$0])?.lowerBound }
    }

    public static func location(in text: String, heading: String?, block: String?) -> Int? {
        let note = ParsedNote(text)
        // frontmatter를 앞에서 잘라 내므로 본문의 줄은 그만큼 늦게 시작한다. 그 밖에 나눌 때 바뀐 글(Windows 줄 끝)은 줄이
        // 맞지 않으므로, 엉뚱한 곳으로 보내지 않고 맨 위에 둔다.
        guard let line = note.line(heading: heading, block: block), text.hasSuffix(note.body) else { return nil }
        let before = note.bodyLines[..<(line - 1)].reduce(0) { $0 + $1.utf16.count + 1 }
        return text.utf16.count - note.body.utf16.count + before
    }
}
