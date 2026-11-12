import FolioDomain
import FolioStorage
import Foundation

/// What one answer of the panel has proposed so far, applied in a staged copy of the GIST folder. The panel starts a
/// `folio mcp --propose` per question, so the copy lives as long as the answer and the next question starts from the
/// folder as it is, without the proposals left unapproved.
///
/// The copy is made at the answer's first write, not before: most answers only read, and those read the folder itself.
final class ProposalStage: @unchecked Sendable {
    struct Made {
        /// Items it added or changed, by ID, with how (`added`, `changed`).
        var items: [String: String]
        /// GIST-relative paths it wrote.
        var paths: Set<String>
    }

    private(set) var folder: StagedFolder?
    /// One per proposal handed back, in the answer's order, which is the order the panel keeps them in.
    private(set) var made: [Made] = []
    private var unavailable = false

    /// Nil when the folder can't be copied; proposals then go back to running against the folder alone.
    func copy(of gist: URL) -> StagedFolder? {
        if let folder { return folder }
        guard !unavailable else { return nil }
        do { folder = try StagedFolder(copying: gist) } catch { unavailable = true }
        return folder
    }

    var staged: Int { made.filter { !$0.items.isEmpty || !$0.paths.isEmpty }.count }

    func record(_ made: Made) { self.made.append(made) }

    /// Items proposed in this answer and not yet approved, by ID.
    var pending: [String: String] {
        made.reduce(into: [:]) { all, m in
            for (id, kind) in m.items where all[id] == nil || kind == "added" { all[id] = kind }
        }
    }

    /// The earlier proposals a new one builds on, once its dry run against the folder alone has failed: those that made
    /// an item its input names or wrote a file it names. Failing alone but naming none of theirs, it is taken to build
    /// on all of them, since what it read from the copy can't be told apart.
    func earlier(_ input: JSONValue) -> [Int] {
        var words: Set<String> = []
        func walk(_ v: JSONValue) {
            switch v {
            case .string(let s): words.insert(s); words.insert(s.lowercased())
            case .array(let a): a.forEach(walk)
            case .object(let o): o.values.forEach(walk)
            default: break
            }
        }
        walk(input)
        let named = made.indices.filter { i in
            made[i].items.keys.contains { words.contains($0) || words.contains($0.lowercased()) }
                || made[i].paths.contains { path in words.contains { !$0.isEmpty && (path == $0 || path.hasSuffix("/" + $0)) } }
        }
        return named.isEmpty ? made.indices.filter { !made[$0].items.isEmpty || !made[$0].paths.isEmpty } : named
    }

    /// Read off a write's `--json` result (`WriteResult`).
    static func made(from output: String) -> Made {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(output.utf8)) else { return Made(items: [:], paths: []) }
        var items: [String: String] = [:]
        var paths: Set<String> = []
        if case .array(let changes)? = value["changes"] {
            for c in changes {
                guard case .string(let kind)? = c["kind"] else { continue }
                if case .string(let path)? = c["path"] { paths.insert(path) }
                if case .string(let to)? = c["to"] { paths.insert(to) }
                // `units/<id>`: an entry of a JSON file. A bare key (`course`) names no item.
                if case .string(let item)? = c["item"], let id = item.split(separator: "/").last.map(String.init), UUID(uuidString: id) != nil,
                   kind == "added" || kind == "changed" {
                    items[id] = items[id] == "added" ? "added" : kind
                }
            }
        }
        if case .string(let id)? = value["made"], items[id] == nil { items[id] = "added" }
        return Made(items: items, paths: paths)
    }

    /// Marks each object of a read result that this answer's proposals added or changed, so Claude doesn't take an
    /// item it only proposed for one already there.
    func marked(_ value: JSONValue) -> JSONValue {
        let pending = pending
        guard !pending.isEmpty else { return value }
        func mark(_ v: JSONValue) -> JSONValue {
            switch v {
            case .object(var o):
                for (k, member) in o { o[k] = mark(member) }
                if case .string(let id)? = o["id"], let kind = pending[id] ?? pending[id.uppercased()] { o["proposed"] = .string(kind) }
                return .object(o)
            case .array(let a): return .array(a.map(mark))
            default: return v
            }
        }
        return mark(value)
    }
}
