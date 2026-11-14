import FolioDomain
import FolioStorage
import Foundation

public protocol Action: Codable, Sendable {
    static var spec: ActionSpec { get }
    func run(_ ctx: ActionContext) throws
}

extension Action {
    public static var command: String { spec.command }
}

extension [Change] {
    public func coalesced() -> [Change] {
        var out: [Change] = []
        var at: [String: Int] = [:]
        for c in self {
            let key = c.path + "\u{0}" + (c.item ?? "") + "\u{0}" + (c.to ?? "")
            guard let i = at[key] else { at[key] = out.count; out.append(c); continue }
            var m = out[i]
            if c.kind == .removed { m.kind = m.kind == .added ? .changed : .removed }
            if let fields = c.fields {
                var merged = m.fields ?? []
                for f in fields {
                    if let j = merged.firstIndex(where: { $0.name == f.name }) { merged[j].after = f.after } else { merged.append(f) }
                }
                m.fields = merged.filter { $0.before != $0.after }
            }
            out[i] = m
        }
        return out
    }
}

func diff<M: Encodable>(_ before: M, _ after: M, path: String) -> [Change] {
    func json(_ m: M) -> [String: JSONValue] {
        guard let data = try? JSONEncoder().encode(m), case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return [:]
        }
        return o
    }

    func stripped(_ v: JSONValue?) -> JSONValue? {
        guard case .object(var o)? = v else { return v }
        o["updatedAt"] = nil
        o["updatedBy"] = nil
        return .object(o)
    }

    func byID(_ v: JSONValue?) -> [String: JSONValue]? {
        guard case .array(let items)? = v else { return nil }
        var result: [String: JSONValue] = [:]
        for item in items {
            guard case .string(let id)? = item["id"] else { return nil }
            result[id] = item
        }
        return result
    }

    func fields(_ name: String, _ old: JSONValue?, _ new: JSONValue?) -> [Change.Field] {
        guard case .object(let o)? = stripped(old), case .object(let n)? = stripped(new) else {
            return [Change.Field(name: name, before: old, after: new)]
        }
        return Set(o.keys).union(n.keys).sorted().filter { o[$0] != n[$0] }.map { Change.Field(name: $0, before: o[$0], after: n[$0]) }
    }

    let (a, b) = (json(before), json(after))
    var changes: [Change] = []
    for key in Set(a.keys).union(b.keys).sorted() where stripped(a[key]) != stripped(b[key]) {
        if let old = byID(a[key]) ?? (a[key] == nil ? [:] : nil), let new = byID(b[key]) ?? (b[key] == nil ? [:] : nil) {
            for id in Set(old.keys).union(new.keys).sorted() where stripped(old[id]) != stripped(new[id]) {
                let kind: Change.Kind = old[id] == nil ? .added : new[id] == nil ? .removed : .changed
                changes.append(Change(kind, path, item: "\(key)/\(id)", fields: kind == .changed ? fields(key, old[id], new[id]) : nil))
            }
        } else {
            changes.append(Change(.changed, path, item: key, fields: fields(key, a[key], b[key])))
        }
    }
    return changes
}
