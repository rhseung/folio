import Foundation

/// JSON read with where each value was written, so a caret in a `cb-table` block can be traced to the cell it is in.
/// Foundation's parsers give values only. Numbers keep the text they were written as, and objects their keys' order,
/// so fields the table editor doesn't know are written back as they were.
struct JSONNode: Equatable, Sendable {
    indirect enum Kind: Equatable, Sendable {
        case null
        case bool(Bool)
        case number(String)
        case string(String)
        case array([JSONNode])
        case object([Member])
    }

    struct Member: Equatable, Sendable {
        var key: String
        var value: JSONNode
    }

    var kind: Kind
    /// UTF-16 offsets in the text it was read from.
    var range: NSRange

    init(_ kind: Kind, range: NSRange = NSRange(location: NSNotFound, length: 0)) {
        self.kind = kind
        self.range = range
    }

    subscript(key: String) -> JSONNode? {
        guard case .object(let members) = kind else { return nil }
        return members.first { $0.key == key }?.value
    }

    var members: [Member]? { if case .object(let m) = kind { m } else { nil } }
    var items: [JSONNode]? { if case .array(let a) = kind { a } else { nil } }
    var string: String? { if case .string(let s) = kind { s } else { nil } }
    var bool: Bool? { if case .bool(let b) = kind { b } else { nil } }
    var number: Double? { if case .number(let n) = kind { Double(n) } else { nil } }

    /// Written on one line, `{"a": 1, "b": [true]}`.
    var text: String {
        switch kind {
        case .null: "null"
        case .bool(let b): b ? "true" : "false"
        case .number(let n): n
        case .string(let s): Self.quoted(s)
        case .array(let items): "[" + items.map(\.text).joined(separator: ", ") + "]"
        case .object(let members): "{" + members.map { Self.quoted($0.key) + ": " + $0.value.text }.joined(separator: ", ") + "}"
        }
    }

    static func quoted(_ s: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    // MARK: Reading

    static func parse(_ text: String) -> JSONNode? {
        var reader = Reader(units: Array(text.utf16))
        reader.space()
        guard let value = reader.value() else { return nil }
        reader.space()
        return reader.at == reader.units.count ? value : nil
    }

    private struct Reader {
        let units: [UInt16]
        var at = 0

        var peek: UInt16? { at < units.count ? units[at] : nil }

        mutating func space() {
            while let c = peek, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { at += 1 }
        }

        mutating func literal(_ word: String) -> Bool {
            let w = Array(word.utf16)
            guard at + w.count <= units.count, Array(units[at..<(at + w.count)]) == w else { return false }
            at += w.count
            return true
        }

        mutating func value() -> JSONNode? {
            let start = at
            func node(_ kind: Kind) -> JSONNode { JSONNode(kind, range: NSRange(location: start, length: at - start)) }
            switch peek {
            case 0x7B?: // {
                at += 1
                var members: [Member] = []
                space()
                if peek == 0x7D { at += 1; return node(.object(members)) }
                while true {
                    space()
                    guard peek == 0x22, let key = string() else { return nil }
                    space()
                    guard peek == 0x3A else { return nil }
                    at += 1
                    space()
                    guard let v = value() else { return nil }
                    members.append(Member(key: key, value: v))
                    space()
                    if peek == 0x2C { at += 1; continue }
                    guard peek == 0x7D else { return nil }
                    at += 1
                    return node(.object(members))
                }
            case 0x5B?: // [
                at += 1
                var items: [JSONNode] = []
                space()
                if peek == 0x5D { at += 1; return node(.array(items)) }
                while true {
                    space()
                    guard let v = value() else { return nil }
                    items.append(v)
                    space()
                    if peek == 0x2C { at += 1; continue }
                    guard peek == 0x5D else { return nil }
                    at += 1
                    return node(.array(items))
                }
            case 0x22?:
                return string().map { node(.string($0)) }
            case 0x74?: return literal("true") ? node(.bool(true)) : nil
            case 0x66?: return literal("false") ? node(.bool(false)) : nil
            case 0x6E?: return literal("null") ? node(.null) : nil
            default:
                while let c = peek, (0x30...0x39).contains(c) || [0x2D, 0x2B, 0x2E, 0x65, 0x45].contains(c) { at += 1 }
                let n = String(utf16CodeUnits: Array(units[start..<at]), count: at - start)
                return at > start && Double(n) != nil ? node(.number(n)) : nil
            }
        }

        mutating func string() -> String? {
            at += 1
            var out: [UInt16] = []
            while let c = peek {
                at += 1
                switch c {
                case 0x22:
                    return String(utf16CodeUnits: out, count: out.count)
                case 0x5C:
                    guard let e = peek else { return nil }
                    at += 1
                    switch e {
                    case 0x22, 0x5C, 0x2F: out.append(e)
                    case 0x62: out.append(0x08)
                    case 0x66: out.append(0x0C)
                    case 0x6E: out.append(0x0A)
                    case 0x72: out.append(0x0D)
                    case 0x74: out.append(0x09)
                    case 0x75:
                        guard at + 4 <= units.count, let v = UInt16(String(utf16CodeUnits: Array(units[at..<(at + 4)]), count: 4), radix: 16) else { return nil }
                        at += 4
                        out.append(v)
                    default: return nil
                    }
                case 0x00...0x1F:
                    return nil
                default:
                    out.append(c)
                }
            }
            return nil
        }
    }
}
