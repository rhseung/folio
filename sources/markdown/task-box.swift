public enum TaskBox {
    public static func toggled(_ line: String) -> String? {
        guard let m = line.firstMatch(of: /^(?:[ \t]*>)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\](?=[ \t]|$)/) else { return nil }
        let mark = m.output.1
        var out = line
        out.replaceSubrange(mark.startIndex..<mark.endIndex, with: mark == " " ? "x" : " ")
        return out
    }
}
