import FolioDomain
import FolioStorage
import Foundation

// 패널은 질문마다 `folio mcp --propose`를 띄우므로, 사본은 답 하나만큼 살고 다음 질문은 승인하지 않은 제안 없이 지금
// 폴더에서 시작한다. 대부분의 답은 읽기만 하고 폴더 자체를 읽으므로, 사본은 답의 첫 쓰기 때 만든다.
final class ProposalStage: @unchecked Sendable {
    struct Made {
        var items: [String: String]
        var paths: Set<String>
    }

    private(set) var folder: StagedFolder?
    private(set) var made: [Made] = []
    private var unavailable = false

    func copy(of gist: URL) -> StagedFolder? {
        if let folder { return folder }
        guard !unavailable else { return nil }
        do { folder = try StagedFolder(copying: gist) } catch { unavailable = true }
        return folder
    }

    var staged: Int { made.filter { !$0.items.isEmpty || !$0.paths.isEmpty }.count }

    func record(_ made: Made) { self.made.append(made) }

    var pending: [String: String] {
        made.reduce(into: [:]) { all, m in
            for (id, kind) in m.items where all[id] == nil || kind == "added" { all[id] = kind }
        }
    }

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

    static func made(from output: String) -> Made {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(output.utf8)) else { return Made(items: [:], paths: []) }
        var items: [String: String] = [:]
        var paths: Set<String> = []
        if case .array(let changes)? = value["changes"] {
            for c in changes {
                guard case .string(let kind)? = c["kind"] else { continue }
                if case .string(let path)? = c["path"] { paths.insert(path) }
                if case .string(let to)? = c["to"] { paths.insert(to) }
                if case .string(let item)? = c["item"], let id = item.split(separator: "/").last.map(String.init),
                    UUID(uuidString: id) != nil,
                    kind == "added" || kind == "changed"
                {
                    items[id] = items[id] == "added" ? "added" : kind
                }
            }
        }
        if case .string(let id)? = value["made"], items[id] == nil { items[id] = "added" }
        return Made(items: items, paths: paths)
    }

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
