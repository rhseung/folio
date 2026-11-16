import Foundation
import Markdown

final class FootnoteBook {
    let definitions: [String: [Markup]]
    private(set) var numbered: [String] = []
    private var uses: [String: Int] = [:]

    init(_ document: Markup) {
        var found: [String: [Markup]] = [:]
        func walk(_ node: Markup) {
            if let p = node as? Paragraph, Self.label(of: p) != nil {
                for (label, inlines) in Self.split(p) where found[Footnotes.key(label)] == nil { found[Footnotes.key(label)] = inlines }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(document)
        definitions = found
    }

    static func label(of node: Markup?) -> String? {
        guard let text = node as? Markdown.Text, text.string.first == Footnotes.marker,
            let m = text.string.prefixMatch(of: Footnotes.maskedStart)
        else { return nil }
        return String(m.1)
    }

    static func label(of p: Paragraph) -> String? { label(of: p.child(at: 0)) }

    static func split(_ p: Paragraph) -> [(String, [Markup])] {
        var out: [(String, [Markup])] = []
        let inlines = Array(p.inlineChildren).map { $0 as Markup }
        for (i, node) in inlines.enumerated() {
            if let label = label(of: node), i == 0 || inlines[i - 1] is SoftBreak {
                if i > 0, !out.isEmpty { out[out.count - 1].1.removeLast() }
                out.append((label, [node]))
            } else if !out.isEmpty {
                out[out.count - 1].1.append(node)
            }
        }
        return out
    }

    func isDefinition(_ p: Paragraph) -> Bool {
        Self.label(of: p).map { definitions[Footnotes.key($0)] != nil } ?? false
    }

    func use(_ label: String) -> (number: Int, use: Int)? {
        let key = Footnotes.key(label)
        guard definitions[key] != nil else { return nil }
        if !numbered.contains(key) { numbered.append(key) }
        uses[key, default: 0] += 1
        return (numbered.firstIndex(of: key)! + 1, uses[key]!)
    }

    func uses(of key: String) -> Int { uses[key] ?? 0 }
}
