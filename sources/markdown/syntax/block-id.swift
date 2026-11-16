import Foundation

public enum BlockID {
    public static var pattern: Regex<(Substring, Substring)> { #/\s\^([A-Za-z0-9-]+)\s*$/# }

    public static func strip(_ text: String) -> (text: String, id: String?) {
        guard let m = text.firstMatch(of: pattern) else { return (text, nil) }
        var t = text
        t.removeSubrange(m.range)
        return (t, String(m.1))
    }
}
