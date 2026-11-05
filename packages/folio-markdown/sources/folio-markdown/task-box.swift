/// A list item's task box, `- [ ]` or `- [x]`, as written on its source line.
public enum TaskBox {
    /// The line with its box ticked or cleared, or nil when the line starts no task item. Quote markers and indents
    /// before the item stay as written.
    public static func toggled(_ line: String) -> String? {
        guard let m = line.firstMatch(of: /^(?:[ \t]*>)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\](?=[ \t]|$)/) else { return nil }
        let mark = m.output.1
        var out = line
        out.replaceSubrange(mark.startIndex..<mark.endIndex, with: mark == " " ? "x" : " ")
        return out
    }
}
