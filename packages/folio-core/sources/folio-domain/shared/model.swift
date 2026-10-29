import Foundation

// The data model as a declaration: each document lists its items, what they point at, what happens to a pointer when
// its target goes, and the checks every save must pass. Rules, cascading removal and name lookup all come from this
// one place, so the app, the CLI and `folio run` can't disagree about them.

/// A rule's stable name. Saves compare violations by rule and subject, never by message, so rewording a message or
/// renaming an item doesn't make a problem the file already had look new.
public struct RuleID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { name = value }
    public var description: String { name }
}

public struct Violation: Hashable, Sendable, CustomStringConvertible {
    public let rule: RuleID
    public let subject: UUID?
    public let message: String

    public init(_ rule: RuleID, subject: UUID?, _ message: String) {
        (self.rule, self.subject, self.message) = (rule, subject, message)
    }

    public static func == (a: Self, b: Self) -> Bool { a.rule == b.rule && a.subject == b.subject }
    public func hash(into h: inout Hasher) {
        h.combine(rule)
        h.combine(subject)
    }
    public var description: String { message }
}

public enum ModelError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case rule(String)
    public var description: String {
        switch self { case .notFound(let s), .rule(let s): s }
    }
}

/// What happens to a pointer when the item it points at is removed.
public enum OnDelete: Sendable {
    /// The pointing item goes too (a component's scores).
    case cascade
    /// The pointer is cleared, or the id dropped from a list.
    case nullify
    /// The removal is refused while anything points at the item.
    case restrict
    /// For a parent pointer: the children take the removed item's parent.
    case reparent
}

public protocol Document: Sendable {
    static var model: Model<Self> { get }
}

extension Document {
    public var violations: Set<Violation> { Self.model.violations(in: self) }

    /// Changes one item, or throws `notFound` naming the item kind.
    public mutating func update<E: Identifiable & Sendable>(_ items: WritableKeyPath<Self, [E]>, _ id: UUID,
                                                           _ change: (inout E) throws -> Void) throws where E.ID == UUID {
        guard let i = self[keyPath: items].firstIndex(where: { $0.id == id }) else {
            throw ModelError.notFound(String(localized: .modelNotFound(Korean.object(Self.model.noun(of: E.self)))))
        }
        try change(&self[keyPath: items][i])
    }

    /// Removes an item and settles everything that points at it, as the model declares.
    public mutating func remove<E: Identifiable & Sendable>(_ type: E.Type, _ id: UUID) throws where E.ID == UUID {
        try Self.model.remove(ObjectIdentifier(type), id, in: &self)
    }

    public func name(of id: UUID) -> String? {
        Self.model.collections.lazy.compactMap { $0.all(self).first { $0.id == id }?.name }.first
    }

    public func names<E>(_ type: E.Type) -> [(id: UUID, name: String)] {
        Self.model.items(of: ObjectIdentifier(type))?.all(self) ?? []
    }
}

// MARK: Declaring

public struct Model<Doc: Sendable>: Sendable {
    let parts: [ModelPart<Doc>]
    /// Where a missing target was looked for, as messages say it: "이 과목에".
    let place: String

    public init(place: String, @ModelBuilder<Doc> _ content: () -> [ModelPart<Doc>]) {
        self.place = place
        parts = content()
    }

    var collections: [AnyItems<Doc>] { parts.compactMap { if case .items(let c) = $0 { c } else { nil } } }

    func items(of kind: ObjectIdentifier) -> AnyItems<Doc>? { collections.first { $0.kind == kind } }

    func noun<E>(of type: E.Type) -> String { items(of: ObjectIdentifier(type))?.noun ?? String(describing: type) }
}

public enum ModelPart<Doc: Sendable>: Sendable {
    case items(AnyItems<Doc>)
    case rule(AnyRule<Doc>)
}

/// The other documents a rule may look at: a course's codes live in the catalog, a catalog row is used by courses.
/// A rule whose document isn't given passes, so checking one file never needs every file.
public struct World: Sendable {
    public var catalog: Catalog?
    public var transcript: Transcript?
    public var courseFiles: [CourseFile]?

    public init(catalog: Catalog? = nil, transcript: Transcript? = nil, courseFiles: [CourseFile]? = nil) {
        (self.catalog, self.transcript, self.courseFiles) = (catalog, transcript, courseFiles)
    }
}

@resultBuilder public enum ModelBuilder<Doc: Sendable> {
    public static func buildExpression(_ items: AnyItems<Doc>) -> [ModelPart<Doc>] { [.items(items)] }
    public static func buildExpression(_ rule: AnyRule<Doc>) -> [ModelPart<Doc>] { [.rule(rule)] }
    public static func buildBlock(_ parts: [ModelPart<Doc>]...) -> [ModelPart<Doc>] { parts.flatMap { $0 } }
}

/// One kind of item in a document. Nested items (an exam's plan) are flattened across their parents.
public struct AnyItems<Doc: Sendable>: Sendable {
    let kind: ObjectIdentifier
    let type: String
    let noun: String
    let all: @Sendable (Doc) -> [(id: UUID, name: String)]
    let checks: @Sendable (Doc, ModelIndex<Doc>) -> [Violation]
    let delete: @Sendable (inout Doc, UUID) -> Void
    let refs: [AnyRef<Doc>]
}

/// A pointer field of one item kind, seen from the document.
struct AnyRef<Doc: Sendable>: Sendable {
    let target: ObjectIdentifier
    let onDelete: OnDelete
    /// Ids of the items whose field points at `id`.
    let holders: @Sendable (Doc, UUID) -> [UUID]
    /// What the item `id` points at.
    let values: @Sendable (Doc, UUID) -> [UUID]
    /// Replaces `id` with `replacement` (nil: clears it, or drops it from a list) in every item pointing at it.
    let detach: @Sendable (inout Doc, UUID, UUID?) -> Void
}

/// A rule on the document as a whole.
public struct AnyRule<Doc: Sendable>: Sendable {
    let check: @Sendable (Doc, ModelIndex<Doc>) -> [Violation]
}

/// The ids and names of every item, built once per check.
struct ModelIndex<Doc: Sendable> {
    let ids: [ObjectIdentifier: Set<UUID>]
    let nouns: [ObjectIdentifier: String]
    let place: String
    let world: World
    let names: [UUID: String]
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

/// Items kept inside other items, such as an exam's study plan.
public func Items<Doc: Sendable, P, E: Identifiable & Sendable>(
    _ parents: WritableKeyPath<Doc, [P]> & Sendable, _ items: WritableKeyPath<P, [E]> & Sendable, noun: String,
    name: KeyPath<E, String> & Sendable, @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    collection(get: { $0[keyPath: parents].flatMap { $0[keyPath: items] } },
               modify: { doc, body in for i in doc[keyPath: parents].indices { body(&doc[keyPath: parents][i][keyPath: items]) } },
               noun: noun, name: { e, _ in e[keyPath: name] }, members())
}

/// The document's one item of a kind, such as a course file's course.
public func One<Doc: Sendable, E: Identifiable & Sendable>(
    _ item: WritableKeyPath<Doc, E> & Sendable, noun: String, name: KeyPath<E, String> & Sendable,
    @MemberBuilder<Doc, E> _ members: () -> [Member<Doc, E>] = { [] }
) -> AnyItems<Doc> where E.ID == UUID {
    collection(get: { [$0[keyPath: item]] },
               modify: { doc, body in
                   var one = [doc[keyPath: item]]
                   body(&one)
                   if let e = one.first { doc[keyPath: item] = e }
               },
               noun: noun, name: { e, _ in e[keyPath: name] }, members())
}

/// A condition on the whole document, such as a range in settings.
public func Rule<Doc: Sendable>(_ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (Doc, World) -> Bool) -> AnyRule<Doc> {
    AnyRule { doc, index in holds(doc, index.world) ? [] : [Violation(rule, subject: nil, message)] }
}

/// A condition on the whole document that can fail for several items. Each failure needs its own subject: two
/// failures of one rule with the same subject count as one.
public func Rule<Doc: Sendable>(_ rule: RuleID, _ failures: @escaping @Sendable (Doc, World) -> [(UUID?, String)]) -> AnyRule<Doc> {
    AnyRule { doc, index in failures(doc, index.world).map { Violation(rule, subject: $0.0, $0.1) } }
}

/// Declares that `a`'s list and `b`'s list mirror each other: `x` lists `y` exactly when `y` lists `x`.
public func Pair<Doc: Sendable, A: Identifiable & Sendable, B: Identifiable & Sendable>(
    _ aItems: KeyPath<Doc, [A]> & Sendable, _ aList: KeyPath<A, [UUID]> & Sendable,
    _ bItems: KeyPath<Doc, [B]> & Sendable, _ bList: KeyPath<B, [UUID]> & Sendable
) -> AnyRule<Doc> where A.ID == UUID, B.ID == UUID {
    let rule = RuleID("\(A.self).\(field(aList))~\(B.self).\(field(bList))")
    return AnyRule { doc, index in
        let bs = Dictionary(doc[keyPath: bItems].map { ($0.id, Set($0[keyPath: bList])) }, uniquingKeysWith: { a, _ in a })
        let aSet = Set(doc[keyPath: aItems].flatMap { a in a[keyPath: aList].map { Pair2(a: a.id, b: $0) } })
        let bSet = Set(doc[keyPath: bItems].flatMap { b in b[keyPath: bList].map { Pair2(a: $0, b: b.id) } })
        // Only pairs whose both ends exist: a dangling id is the ref check's business.
        let aIds = Set(doc[keyPath: aItems].map(\.id))
        return aSet.symmetricDifference(bSet).filter { aIds.contains($0.a) && bs[$0.b] != nil }
            .map { p in
                let a = index.names[p.a] ?? p.a.uuidString, b = index.names[p.b] ?? p.b.uuidString
                let aNoun = index.nouns[ObjectIdentifier(A.self)] ?? "\(A.self)", bNoun = index.nouns[ObjectIdentifier(B.self)] ?? "\(B.self)"
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
                modify(&doc) { items in for i in items.indices where r.points(items[i]).contains(id) { r.detach(&items[i], id, replacement) } }
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

// MARK: Members

public struct Member<Doc: Sendable, E: Sendable>: Sendable {
    let check: @Sendable (E, Doc, _ label: String, ModelIndex<Doc>) -> [Violation]
    let ref: RefInfo<E>?
}

struct RefInfo<E>: Sendable {
    let target: ObjectIdentifier
    let onDelete: OnDelete
    let points: @Sendable (E) -> [UUID]
    let detach: @Sendable (inout E, UUID, UUID?) -> Void
}

@resultBuilder public enum MemberBuilder<Doc: Sendable, E: Sendable> {
    // Without it each line is typed on its own and `Ref(\.field, ...)` can't learn which item it belongs to.
    public static func buildExpression(_ member: Member<Doc, E>) -> [Member<Doc, E>] { [member] }
    /// A shared list of members, such as the course checks a course file and the transcript both apply.
    public static func buildExpression(_ members: [Member<Doc, E>]) -> [Member<Doc, E>] { members }
    public static func buildBlock(_ members: [Member<Doc, E>]...) -> [Member<Doc, E>] { members.flatMap { $0 } }
}

/// A condition each item must meet. `{name}` in the message is the item's display name.
public func Check<Doc: Sendable, E: Identifiable & Sendable>(
    _ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (E, Doc) -> Bool
) -> Member<Doc, E> where E.ID == UUID {
    Member(check: { e, doc, label, _ in
        holds(e, doc) ? [] : [Violation(rule, subject: e.id, message.replacingOccurrences(of: "{name}", with: label))]
    }, ref: nil)
}

/// A condition that needs other documents; it passes when `World` doesn't have them.
public func Check<Doc: Sendable, E: Identifiable & Sendable>(
    _ rule: RuleID, _ message: String, _ holds: @escaping @Sendable (E, Doc, World) -> Bool
) -> Member<Doc, E> where E.ID == UUID {
    Member(check: { e, doc, label, index in
        holds(e, doc, index.world) ? [] : [Violation(rule, subject: e.id, message.replacingOccurrences(of: "{name}", with: label))]
    }, ref: nil)
}

public func NonEmpty<Doc: Sendable, E: Identifiable & Sendable>(
    _ field: KeyPath<E, String> & Sendable, _ message: String
) -> Member<Doc, E> where E.ID == UUID {
    Check(RuleID("\(E.self).\(folioField(field)).empty"), message) { e, _ in !e[keyPath: field].trimmingCharacters(in: .whitespaces).isEmpty }
}

public func Ref<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, UUID> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(field: folioField(field), to: target, label: label, onDelete: onDelete, points: { [$0[keyPath: field]] },
              detach: { e, _, replacement in if let replacement { e[keyPath: field] = replacement } })
}

public func Ref<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, UUID?> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(field: folioField(field), to: target, label: label, onDelete: onDelete, points: { $0[keyPath: field].map { [$0] } ?? [] },
              detach: { e, _, replacement in e[keyPath: field] = replacement })
}

public func Refs<Doc: Sendable, E: Identifiable & Sendable, T>(
    _ field: WritableKeyPath<E, [UUID]> & Sendable, to target: T.Type, as label: String? = nil, onDelete: OnDelete
) -> Member<Doc, E> where E.ID == UUID {
    reference(field: folioField(field), to: target, label: label, onDelete: onDelete, points: { $0[keyPath: field] },
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
            // A target kind the model doesn't list lives in another document; that check needs the other files.
            guard let known = index.ids[kind] else { return [] }
            let noun = index.nouns[ObjectIdentifier(E.self)] ?? "\(E.self)"
            let what = label ?? index.nouns[kind] ?? "\(T.self)"
            return points(e).filter { !known.contains($0) }.map {
                Violation(rule, subject: e.id, String(localized: .modelMissingTarget(noun, name, Korean.subject(what), index.place, "\($0)")))
            }
        },
        ref: RefInfo(target: kind, onDelete: onDelete, points: points, detach: detach))
}

/// `\ScoreEntry.componentId` → `componentId`, for rule names.
func folioField(_ path: AnyKeyPath) -> String { field(path) }

private func field(_ path: AnyKeyPath) -> String {
    let text = String(describing: path)
    return text.split(separator: ".").dropFirst().joined(separator: ".")
}

// MARK: Running

extension Model {
    func index(_ doc: Doc, _ world: World) -> ModelIndex<Doc> {
        ModelIndex(ids: Dictionary(collections.map { ($0.kind, Set($0.all(doc).map(\.id))) }, uniquingKeysWith: { a, b in a.union(b) }),
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

    /// The first message for violations `after` has and `before` didn't: a file that was already broken stays editable.
    public func newViolation(before: Doc, after: Doc, world: World = World()) -> Violation? {
        newViolation(before, in: world, after, in: world)
    }

    /// The same, when the other documents changed too: a catalog edit checked against a course file it doesn't touch.
    public func newViolation(_ before: Doc, in old: World, _ after: Doc, in new: World) -> Violation? {
        let had = violations(in: before, world: old)
        return violations(in: after, world: new).subtracting(had).sorted { ($0.rule.name, $0.message) < ($1.rule.name, $1.message) }.first
    }

    func remove(_ kind: ObjectIdentifier, _ id: UUID, in doc: inout Doc) throws {
        guard let items = items(of: kind), let name = items.all(doc).first(where: { $0.id == id })?.name else {
            throw ModelError.notFound(String(localized: .modelNotFound(Korean.object(items(of: kind)?.noun ?? String(localized: .modelNounItem)))))
        }
        let pointing = collections.flatMap { c in c.refs.filter { $0.target == kind }.map { (c, $0) } }
        for (c, r) in pointing where r.onDelete == .restrict {
            guard let holder = r.holders(doc, id).first else { continue }
            let by = c.all(doc).first { $0.id == holder }?.name ?? ""
            throw ModelError.rule(String(localized: .modelDeleteRestricted(c.noun, Korean.quoted(by, "이", "가"), items.noun, Korean.quoted(name, "을", "를"))))
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

/// Korean particles that depend on whether the word ends in a consonant.
public enum Korean {
    static func hasFinalConsonant(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last(where: { !CharacterSet.whitespaces.contains($0) }),
              (0xAC00...0xD7A3).contains(last.value) else { return false }
        return (last.value - 0xAC00) % 28 != 0
    }

    /// `'중간고사'를`: the particle follows the quoted word, not the quote mark.
    public static func quoted(_ word: String, _ afterConsonant: String, _ afterVowel: String) -> String {
        "'\(word)'" + (hasFinalConsonant(word) ? afterConsonant : afterVowel)
    }

    /// 시험이, 과제가
    public static func subject(_ word: String) -> String { word + (hasFinalConsonant(word) ? "이" : "가") }
    /// 시험을, 과제를
    public static func object(_ word: String) -> String { word + (hasFinalConsonant(word) ? "을" : "를") }
}
