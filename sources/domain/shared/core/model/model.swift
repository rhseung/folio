import Foundation

// MARK: Declaring

public struct Model<Doc: Sendable>: Sendable {
    let parts: [ModelPart<Doc>]
    let place: String

    public init(place: String, @ModelBuilder<Doc> _ content: () -> [ModelPart<Doc>]) {
        self.place = place
        parts = content()
    }

    var collections: [AnyItems<Doc>] { parts.compactMap { if case .items(let c) = $0 { c } else { nil } } }

    func items(of kind: ObjectIdentifier) -> AnyItems<Doc>? { collections.first { $0.kind == kind } }

    func noun<E>(of type: E.Type) -> String { items(of: ObjectIdentifier(type))?.noun ?? String(describing: type) }
}

public func Items<Doc: Sendable, E: Identifiable & Sendable>(
    _ items: WritableKeyPath<Doc, [E]> & Sendable, noun: String, name: @escaping @Sendable (E, Doc) -> String,
    @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    collection(get: { $0[keyPath: items] }, modify: { doc, body in body(&doc[keyPath: items]) }, noun: noun, name: name, members())
}

public func Items<Doc: Sendable, E: Identifiable & Sendable>(
    _ items: WritableKeyPath<Doc, [E]> & Sendable, noun: String, name: KeyPath<E, String> & Sendable,
    @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    Items(items, noun: noun, name: { e, _ in e[keyPath: name] }, members)
}

public func Items<Doc: Sendable, P, E: Identifiable & Sendable>(
    _ parents: WritableKeyPath<Doc, [P]> & Sendable, _ items: WritableKeyPath<P, [E]> & Sendable, noun: String,
    name: KeyPath<E, String> & Sendable, @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    collection(
        get: { $0[keyPath: parents].flatMap { $0[keyPath: items] } },
        modify: { doc, body in for i in doc[keyPath: parents].indices { body(&doc[keyPath: parents][i][keyPath: items]) } },
        noun: noun, name: { e, _ in e[keyPath: name] }, members())
}

public func One<Doc: Sendable, E: Identifiable & Sendable>(
    _ item: WritableKeyPath<Doc, E> & Sendable, noun: String, name: KeyPath<E, String> & Sendable,
    @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    collection(
        get: { [$0[keyPath: item]] },
        modify: { doc, body in
            var one = [doc[keyPath: item]]
            body(&one)
            if let e = one.first { doc[keyPath: item] = e }
        },
        noun: noun, name: { e, _ in e[keyPath: name] }, members())
}

public func Rule<Doc: Sendable>(_ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (Doc, World) -> Bool) -> AnyRule<Doc> {
    AnyRule { doc, index in holds(doc, index.world) ? [] : [Violation(rule, subject: nil, message)] }
}

// 실패마다 대상이 따로 있어야 한다. 한 규칙의 두 실패가 대상이 같으면 하나로 센다.
public func Rule<Doc: Sendable>(_ rule: RuleID, _ failures: @escaping @Sendable (Doc, World) -> [(UUID?, String)]) -> AnyRule<Doc> {
    AnyRule { doc, index in failures(doc, index.world).map { Violation(rule, subject: $0.0, $0.1) } }
}

public func Pair<Doc: Sendable, A: Identifiable & Sendable, B: Identifiable & Sendable>(
    _ aItems: KeyPath<Doc, [A]> & Sendable, _ aList: KeyPath<A, [UUID]> & Sendable,
    _ bItems: KeyPath<Doc, [B]> & Sendable, _ bList: KeyPath<B, [UUID]> & Sendable
) -> AnyRule<Doc> where A.ID == UUID, B.ID == UUID {
    let rule = RuleID("\(A.self).\(field(aList))~\(B.self).\(field(bList))")
    return AnyRule { doc, index in
        let bs = Dictionary(doc[keyPath: bItems].map { ($0.id, Set($0[keyPath: bList])) }, uniquingKeysWith: { a, _ in a })
        let aSet = Set(doc[keyPath: aItems].flatMap { a in a[keyPath: aList].map { Pair2(a: a.id, b: $0) } })
        let bSet = Set(doc[keyPath: bItems].flatMap { b in b[keyPath: bList].map { Pair2(a: $0, b: b.id) } })
        let aIds = Set(doc[keyPath: aItems].map(\.id))
        return aSet.symmetricDifference(bSet).filter { aIds.contains($0.a) && bs[$0.b] != nil }
            .map { p in
                let a = index.names[p.a] ?? p.a.uuidString, b = index.names[p.b] ?? p.b.uuidString
                let aNoun = index.nouns[ObjectIdentifier(A.self)] ?? "\(A.self)",
                    bNoun = index.nouns[ObjectIdentifier(B.self)] ?? "\(B.self)"
                return Violation(rule, subject: p.a, String(localized: .modelPairOneSided(aNoun, Korean.quoted(a, "과", "와"), bNoun, b)))
            }
    }
}

private struct Pair2: Hashable { let a: UUID, b: UUID }

private func collection<Doc: Sendable, E: Identifiable & Sendable>(
    get: @escaping @Sendable (Doc) -> [E], modify: @escaping @Sendable (inout Doc, (inout [E]) -> Void) -> Void,
    noun: String, name: @escaping @Sendable (E, Doc) -> String, _ members: [Member<Doc, E>]
) -> AnyItems<Doc> where E.ID == UUID {
    let type = String(describing: E.self)
    let refs = members.compactMap(\.ref).map { r in
        AnyRef<Doc>(
            target: r.target, onDelete: r.onDelete,
            holders: { doc, id in get(doc).filter { r.points($0).contains(id) }.map(\.id) },
            values: { doc, id in get(doc).first { $0.id == id }.map(r.points) ?? [] },
            detach: { doc, id, replacement in
                modify(&doc) { items in
                    for i in items.indices where r.points(items[i]).contains(id) { r.detach(&items[i], id, replacement) }
                }
            })
    }
    return AnyItems(
        kind: ObjectIdentifier(E.self), type: type, noun: noun,
        all: { doc in get(doc).map { ($0.id, name($0, doc)) } },
        checks: { doc, index in
            let items = get(doc)
            var out: [Violation] = []
            var seen = Set<UUID>()
            for e in items where !seen.insert(e.id).inserted {
                out.append(Violation(RuleID("\(type).id"), subject: e.id, String(localized: .modelDuplicateId(noun, "\(e.id)"))))
            }
            for e in items {
                let label = name(e, doc)
                for m in members { out += m.check(e, doc, label, index) }
            }
            return out
        },
        delete: { doc, id in modify(&doc) { $0.removeAll { $0.id == id } } },
        refs: refs)
}

public func Check<Doc: Sendable, E: Identifiable & Sendable>(
    _ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (E, Doc) -> Bool
) -> Member<Doc, E> where E.ID == UUID {
    Member(
        check: { e, doc, label, _ in
            holds(e, doc) ? [] : [Violation(rule, subject: e.id, message.replacingOccurrences(of: "{name}", with: label))]
        }, ref: nil)
}

public func Check<Doc: Sendable, E: Identifiable & Sendable>(
    _ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (E, Doc, World) -> Bool
) -> Member<Doc, E> where E.ID == UUID {
    Member(
        check: { e, doc, label, index in
            holds(e, doc, index.world) ? [] : [Violation(rule, subject: e.id, message.replacingOccurrences(of: "{name}", with: label))]
        }, ref: nil)
}

public func NonEmpty<Doc: Sendable, E: Identifiable & Sendable>(
    _ field: KeyPath<E, String> & Sendable, _ message: String
) -> Member<Doc, E> where E.ID == UUID {
    Check(RuleID("\(E.self).\(folioField(field)).empty"), message) { e, _ in !e[keyPath: field].trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public func Ref<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, UUID> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(
        field: folioField(field), to: target, label: label, onDelete: onDelete, points: { [$0[keyPath: field]] },
        detach: { e, _, replacement in if let replacement { e[keyPath: field] = replacement } })
}

public func Ref<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, UUID?> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(
        field: folioField(field), to: target, label: label, onDelete: onDelete, points: { $0[keyPath: field].map { [$0] } ?? [] },
        detach: { e, _, replacement in e[keyPath: field] = replacement })
}

public func Refs<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, [UUID]> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(
        field: folioField(field), to: target, label: label, onDelete: onDelete, points: { $0[keyPath: field] },
        detach: { e, id, replacement in
            e[keyPath: field] = e[keyPath: field].compactMap { $0 == id ? replacement : $0 }
        })
}

private func reference<Doc: Sendable, E: Identifiable & Sendable, T>(
    field: String, to target: T.Type, label: String?, onDelete: OnDelete, points: @escaping @Sendable (E) -> [UUID],
    detach: @escaping @Sendable (inout E, UUID, UUID?) -> Void
) -> Member<Doc, E> where E.ID == UUID {
    let kind = ObjectIdentifier(target)
    let rule = RuleID("\(E.self).\(field)")
    return Member(
        check: { e, _, name, index in
            guard let known = index.ids[kind] else { return [] }
            let noun = index.nouns[ObjectIdentifier(E.self)] ?? "\(E.self)"
            let what = label ?? index.nouns[kind] ?? "\(T.self)"
            return points(e).filter { !known.contains($0) }.map {
                Violation(
                    rule, subject: e.id, String(localized: .modelMissingTarget(noun, name, Korean.subject(what), index.place, "\($0)")))
            }
        },
        ref: RefInfo(target: kind, onDelete: onDelete, points: points, detach: detach))
}

func folioField(_ path: AnyKeyPath) -> String { field(path) }

private func field(_ path: AnyKeyPath) -> String {
    let text = String(describing: path)
    return text.split(separator: ".").dropFirst().joined(separator: ".")
}

// MARK: Running

extension Model {
    func index(_ doc: Doc, _ world: World) -> ModelIndex<Doc> {
        ModelIndex(
            ids: Dictionary(collections.map { ($0.kind, Set($0.all(doc).map(\.id))) }, uniquingKeysWith: { a, b in a.union(b) }),
            nouns: Dictionary(collections.map { ($0.kind, $0.noun) }, uniquingKeysWith: { a, _ in a }), place: place, world: world,
            names: Dictionary(collections.flatMap { $0.all(doc) }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }))
    }

    public func violations(in doc: Doc, world: World = World()) -> Set<Violation> {
        let index = index(doc, world)
        var out: [Violation] = []
        for part in parts {
            switch part {
            case .items(let c): out += c.checks(doc, index)
            case .rule(let r): out += r.check(doc, index)
            }
        }
        return Set(out)
    }

    // 이미 깨진 파일도 고칠 수 있도록, `before`에 없던 위반만 본다.
    public func newViolation(before: Doc, after: Doc, world: World = World()) -> Violation? {
        newViolation(before, in: world, after, in: world)
    }

    public func newViolation(_ before: Doc, in old: World, _ after: Doc, in new: World) -> Violation? {
        let had = violations(in: before, world: old)
        return violations(in: after, world: new).subtracting(had).sorted { ($0.rule.name, $0.message) < ($1.rule.name, $1.message) }.first
    }

    func remove(_ kind: ObjectIdentifier, _ id: UUID, in doc: inout Doc) throws {
        guard let items = items(of: kind), let name = items.all(doc).first(where: { $0.id == id })?.name else {
            throw ModelError.notFound(
                String(localized: .modelNotFound(Korean.object(items(of: kind)?.noun ?? String(localized: .modelNounItem)))))
        }

        let pointing = collections.flatMap { c in c.refs.filter { $0.target == kind }.map { (c, $0) } }
        for (c, r) in pointing where r.onDelete == .restrict {
            guard let holder = r.holders(doc, id).first else { continue }
            let by = c.all(doc).first { $0.id == holder }?.name ?? ""
            throw ModelError.rule(
                String(localized: .modelDeleteRestricted(c.noun, Korean.quoted(by, "이", "가"), items.noun, Korean.quoted(name, "을", "를"))))
        }

        let cascaded = pointing.filter { $0.1.onDelete == .cascade }.map { ($0.0.kind, $0.1.holders(doc, id)) }
        let parent = pointing.first { $0.0.kind == kind && $0.1.onDelete == .reparent }.flatMap { $0.1.values(doc, id).first }
        items.delete(&doc, id)
        for (_, r) in pointing {
            switch r.onDelete {
            case .nullify: r.detach(&doc, id, nil)
            case .reparent: r.detach(&doc, id, parent)
            case .cascade, .restrict: break
            }
        }

        for (holderKind, holders) in cascaded {
            for h in holders where self.items(of: holderKind)?.all(doc).contains(where: { $0.id == h }) == true {
                try remove(holderKind, h, in: &doc)
            }
        }
    }
}
