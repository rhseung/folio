import Foundation

extension ParsedNote {
    /// The body line (1-based) a link to a heading or block lands on: the heading's own line, or the first line of the
    /// block an embed of it would show (its list item, or its paragraph or callout). Nil without either, or when the
    /// note has no such heading or block.
    public func line(heading: String?, block: String?) -> Int? {
        if let block {
            guard let (top, item) = blockLines(block) else { return nil }
            return (item ?? top).lowerBound
        }
        guard let heading else { return nil }
        let tops = Array(document.children)
        return headingIndex(heading, in: tops).flatMap { lines(of: tops[$0])?.lowerBound }
    }

    /// Where in `text` (in UTF-16 units, as text views count) a link to a heading or block lands.
    public static func location(in text: String, heading: String?, block: String?) -> Int? {
        let note = ParsedNote(text)
        // The frontmatter is cut off the front, so the body's lines start that much later in the text; text the split
        // changed otherwise (Windows line ends) no longer lines up, and is better left at the top than sent astray.
        guard let line = note.line(heading: heading, block: block), text.hasSuffix(note.body) else { return nil }
        let before = note.bodyLines[..<(line - 1)].reduce(0) { $0 + $1.utf16.count + 1 }
        return text.utf16.count - note.body.utf16.count + before
    }
}
