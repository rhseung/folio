import Foundation

enum SourceLines {
    static func content(_ line: NSRange, in text: NSString) -> NSRange {
        var length = line.length
        if length > 0, text.character(at: line.location + length - 1) == 0x0A { length -= 1 }
        return NSRange(location: line.location, length: length)
    }

    static func blockEnd(_ text: NSString, after line: NSRange) -> Int {
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            let content = content(next, in: text)
            let s = text.substring(with: content)
            if s.trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                return content.location + (s as NSString).range(of: "$$", options: .backwards).location
            }
            at = NSMaxRange(next)
        }
        return text.length
    }

    static func fenceEnd(_ text: NSString, after line: NSRange, open: Fence) -> Int {
        var end = NSMaxRange(content(line, in: text))
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            let body = content(next, in: text)
            if let f = Fence(text.substring(with: body)), f.closes(open) { return end }
            end = NSMaxRange(body)
            at = NSMaxRange(next)
        }
        return text.length
    }

    static func displayOpener(_ line: String) -> Int? {
        let prefix = line.prefix { $0 == " " || $0 == ">" }.utf16.count
        guard (line as NSString).substring(from: prefix).hasPrefix("$$") else { return nil }
        return prefix + 2
    }
}
