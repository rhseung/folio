/// YAML frontmatter limited to what notes use: `key: value`, `key: [a, b]` and a `- item` block list under `key:`.
/// Lines it doesn't understand are kept verbatim, so notes written elsewhere (e.g. Obsidian) survive a save.
public struct Frontmatter: Equatable, Sendable {
    enum Line: Equatable, Sendable {
        /// `block` holds the indented or `- ` lines under the key, kept verbatim: Obsidian writes lists that way.
        case field(key: String, value: String, block: [String] = [])
        case raw(String)
    }

    var lines: [Line]

    public init() {
        lines = []
    }

    static let delimiter = "---"

    /// Splits `text` into frontmatter and body. Text without a leading `---` block has empty frontmatter.
    public static func split(_ text: String) -> (frontmatter: Frontmatter, body: String) {
        // Files saved on Windows: "\r\n" is one Character, so splitting on "\n" would see one long line.
        var text = text.replacing("\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard all.first == delimiter, let end = all.dropFirst().firstIndex(of: delimiter) else {
            return (Frontmatter(), text)
        }
        let header = all[1..<end]
        all.removeSubrange(0...end)
        var fm = Frontmatter()
        for line in header {
            let continues = line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("- ") || line == "-"
            if continues, case .field(let k, let v, let block)? = fm.lines.last {
                fm.lines[fm.lines.count - 1] = .field(key: k, value: v, block: block + [line])
                continue
            }
            guard !continues, let colon = line.firstIndex(of: ":") else { fm.lines.append(.raw(line)); continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fm.lines.append(key.isEmpty ? .raw(line) : .field(key: key, value: value))
        }
        return (fm, all.joined(separator: "\n"))
    }

    public subscript(key: String) -> String? {
        get {
            for case .field(let k, let v, _) in lines where k == key { return Self.unquote(v) }
            return nil
        }
        set {
            let index = lines.firstIndex { if case .field(let k, _, _) = $0 { k == key } else { false } }
            switch (index, newValue) {
            case (let i?, let v?): lines[i] = .field(key: key, value: Self.quote(v))
            case (let i?, nil): lines.remove(at: i)
            case (nil, let v?): lines.append(.field(key: key, value: Self.quote(v)))
            case (nil, nil): break
            }
        }
    }

    public func list(_ key: String) -> [String] {
        guard case .field(_, let raw, let block)? = lines.first(where: { if case .field(key, _, _) = $0 { true } else { false } }) else { return [] }
        if raw.isEmpty {
            return block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("-") }
                .map { Self.unquote($0.dropFirst().trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
        }
        let inner = raw.hasPrefix("[") && raw.hasSuffix("]") ? String(raw.dropFirst().dropLast()) : raw
        return inner.split(separator: ",").map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    public mutating func setList(_ key: String, _ values: [String]) {
        // Unchanged lists keep their own layout, so a save doesn't rewrite an Obsidian block list.
        guard values != list(key) else { return }
        let value = values.isEmpty ? nil : "[" + values.map(Self.quote).joined(separator: ", ") + "]"
        let index = lines.firstIndex { if case .field(let k, _, _) = $0 { k == key } else { false } }
        switch (index, value) {
        case (let i?, let v?): lines[i] = .field(key: key, value: v)
        case (let i?, nil): lines.remove(at: i)
        case (nil, let v?): lines.append(.field(key: key, value: v))
        case (nil, nil): break
        }
    }

    public var isEmpty: Bool { lines.isEmpty }

    /// `---` block followed by `body`. Without fields, just the body.
    public func render(body: String) -> String {
        guard !lines.isEmpty else { return body }
        let header = lines.map { line in
            switch line {
            case .field(let k, let v, let block): ([v.isEmpty ? "\(k):" : "\(k): \(v)"] + block).joined(separator: "\n")
            case .raw(let r): r
            }
        }
        return ([Self.delimiter] + header + [Self.delimiter]).joined(separator: "\n") + "\n" + body
    }

    static func unquote(_ s: String) -> String {
        guard s.count >= 2, let first = s.first, first == s.last, first == "\"" || first == "'" else { return s }
        return String(s.dropFirst().dropLast())
    }

    static func quote(_ s: String) -> String {
        let needsQuotes = s.isEmpty || s.contains(where: { ":#[]{},\"'".contains($0) }) || s.first == " " || s.last == " "
        return needsQuotes ? "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\"" : s
    }
}
