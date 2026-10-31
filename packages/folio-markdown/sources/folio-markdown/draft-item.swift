import Foundation

/// A lone `-` indented past the line above is a list item being started (Enter, then Tab), but CommonMark reads it as a
/// setext underline and makes that line a heading until the item has text. Its dash is swapped for a look-alike of the
/// same length, so offsets and lines still match the source.
public enum DraftItem {
    public static let lookAlike: Character = "\u{2010}"

    /// UTF-16 offsets of such dashes.
    public static func dashes(in text: String) -> [Int] {
        var out: [Int] = []
        var offset = 0
        var previous: Substring?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let previous, !previous.allSatisfy(\.isWhitespace), line.trimmingCharacters(in: .whitespaces) == "-" {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                if indent.count > previous.prefix(while: { $0 == " " || $0 == "\t" }).count {
                    out.append(offset + indent.utf16.count)
                }
            }
            previous = line
            offset += line.utf16.count + 1
        }
        return out
    }

    public static func mask(_ text: String) -> String {
        let at = dashes(in: text)
        guard !at.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for i in at { out.replaceCharacters(in: NSRange(location: i, length: 1), with: String(lookAlike)) }
        return out as String
    }
}
