import FolioDomain
import FolioMarkdown
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MathScan {
    struct Inline { let range: NSRange; let tex: String }
    struct Block {
        let lines: ClosedRange<Int>
        let tex: String
        let ranges: [NSRange]
        var syntax: MathSyntax?
    }

    var inline: [Inline] = []
    var blocks: [Block] = []

    init(text: String, lines: [NSRange]) {
        let ns = text as NSString
        var fence: String?
        var fenced: (syntax: MathSyntax, first: Int)?
        var fencedBlocks: [Block] = []
        func closeFenced(last: Int) {
            guard let open = fenced, open.first <= last else { return }
            let ranges = Array(lines[open.first...last])
            let tex = ranges.map { ns.substring(with: $0) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !tex.isEmpty { fencedBlocks.append(Block(lines: open.first...last, tex: tex, ranges: ranges, syntax: open.syntax)) }
        }

        var i = 0
        while i < lines.count {
            let line = ns.substring(with: lines[i])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { i += 1 }
            if let open = fence {
                if trimmed.hasPrefix(open) {
                    fence = nil
                    closeFenced(last: i - 1)
                    fenced = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                let info = String(trimmed.drop { $0 == "`" || $0 == "~" })
                fenced = MathFence.syntax(info).map { MathSyntax($0) }.map { (syntax: $0, first: i + 1) }
                continue
            }
            let prefix = line.prefix { $0 == " " || $0 == ">" }.utf16.count
            if (line as NSString).substring(from: prefix).hasPrefix("$$") {
                let first = i
                var body = (line as NSString).substring(from: prefix + 2).trimmingCharacters(in: .whitespaces)
                var ranges = [NSRange(location: lines[i].location + prefix, length: lines[i].length - prefix)]
                while !body.hasSuffix("$$"), i + 1 < lines.count {
                    i += 1
                    let next = ns.substring(with: lines[i])
                    let cut = min(prefix, next.prefix { $0 == " " || $0 == ">" }.utf16.count)
                    body += "\n" + (next as NSString).substring(from: cut)
                    ranges.append(NSRange(location: lines[i].location + cut, length: lines[i].length - cut))
                }
                if body.hasSuffix("$$") { body.removeLast(2) }
                blocks.append(Block(lines: first...i, tex: body.trimmingCharacters(in: .whitespacesAndNewlines), ranges: ranges))
                continue
            }
            scanInline(line, at: lines[i].location)
        }
        if fence != nil { closeFenced(last: lines.count - 1) }
        blocks += fencedBlocks
    }

    private mutating func scanInline(_ line: String, at offset: Int) {
        let chars = Array(line.utf16)
        var k = 0
        while k < chars.count {
            let c = chars[k]
            if c == 0x5C, k + 1 < chars.count, chars[k + 1] == 0x24 { k += 2; continue }
            if c == 0x60 {
                var n = 0
                while k + n < chars.count, chars[k + n] == 0x60 { n += 1 }
                var j = k + n
                var closed = false
                while j + n <= chars.count {
                    if chars[j..<(j + n)].allSatisfy({ $0 == 0x60 }) { closed = true; break }
                    j += 1
                }
                k = closed ? j + n : k + n
                continue
            }
            if c == 0x24 {
                var j = k + 1
                while j < chars.count, !(chars[j] == 0x24 && chars[j - 1] != 0x5C) { j += 1 }
                if j < chars.count, j > k + 1, chars[k + 1] != 0x20, chars[j - 1] != 0x20 {
                    let tex = String(utf16CodeUnits: Array(chars[(k + 1)..<j]), count: j - k - 1)
                    inline.append(Inline(range: NSRange(location: offset + k, length: j - k + 1), tex: tex))
                    k = j + 1
                    continue
                }
            }
            k += 1
        }
    }

    // 마크다운 파서가 TeX 안의 강조나 이스케이프를 읽지 않도록, 수식을 같은 길이의 빈칸으로 지운 텍스트를 넘긴다.
    func masked(_ text: String) -> String {
        let out = NSMutableString(string: text)
        for r in inline.map(\.range) + blocks.flatMap(\.ranges) {
            out.replaceCharacters(in: r, with: String(repeating: "x", count: r.length))
        }
        return out as String
    }

    func covers(_ r: NSRange) -> Bool {
        (inline.map(\.range) + blocks.flatMap(\.ranges)).contains { NSIntersectionRange($0, r).length > 0 }
    }
}
