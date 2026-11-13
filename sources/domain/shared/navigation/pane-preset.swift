import Foundation

public struct PanePreset: Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        case lecture
        case classNote
        case reviewNote
        case quiz
    }

    public enum Slot: Hashable, Sendable {
        case role(Role)
        case link(AppLink)

        public var role: Role? {
            if case .role(let role) = self { role } else { nil }
        }
    }

    public var id: String
    public var name: String?
    public var slots: [Slot]
    public var shares: [Double]
    public var focus: Role?

    public init(id: String, roles: [Role], shares: [Double], focus: Role? = nil) {
        self.init(id: id, name: nil, slots: roles.map(Slot.role), shares: shares)
        self.focus = focus
    }

    public init(id: String = UUID().uuidString, name: String?, slots: [Slot], shares: [Double]) {
        self.id = id
        self.name = name
        self.slots = slots
        self.shares = shares
    }

    public static let inClass = PanePreset(id: "in-class", roles: [.lecture, .classNote], shares: [0.55, 0.45], focus: .classNote)
    public static let review = PanePreset(
        id: "review", roles: [.lecture, .classNote, .reviewNote], shares: [0.4, 0.3, 0.3], focus: .reviewNote)
    public static let builtIn = [inClass, review]

    public var roles: [Role] { slots.compactMap(\.role) }
    public var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }
    public var needsClass: Bool { slots.contains { $0.role != nil } }

    public var opensClass: Bool { roles.contains(.lecture) || roles.contains(.classNote) }

    public static func links(session: Session, course: UUID) -> [Role: [AppLink]] {
        [
            .lecture: session.materials.map { AppLink(.material, $0.materialId, anchor: $0.firstPage.map(AppLink.Anchor.page)) },
            .classNote: session.roughNoteId.map { [AppLink(.note, $0)] } ?? [],
            .reviewNote: session.reviewNoteId.map { [AppLink(.note, $0)] } ?? [],
            .quiz: [.course(course, page: .quiz)],
        ]
    }

    public func layout(_ links: [Role: [AppLink]], focus: Role? = nil, spreads: Bool = true) -> PaneLayout? {
        var taken: [Role: Int] = [:]
        let filled: [[AppLink]] = slots.enumerated().map { i, slot in
            switch slot {
            case .link(let link): return [link]
            case .role(let role):
                let all = links[role] ?? []
                let k = taken[role, default: 0]
                taken[role] = k + 1
                guard k < all.count else { return [] }
                let last = !slots[(i + 1)...].contains(.role(role))
                return last && spreads ? Array(all[k...]) : [all[k]]
            }
        }

        var chosen: [AppLink] = []
        var widths: [Double] = []
        var focused: Int?
        for (slot, (links, share)) in zip(slots, zip(filled, shares)) where !links.isEmpty {
            if let focus, slot.role == focus, focused == nil { focused = chosen.count }
            for link in links {
                chosen.append(link)
                widths.append(share / Double(links.count))
            }
        }

        guard var layout = PaneLayout(links: chosen, shares: widths) else { return nil }
        if let focused { layout.press(focused) }
        return layout
    }

    public func startLayout(_ links: [Role: [AppLink]]) -> PaneLayout? {
        guard let layout = layout(links, focus: .classNote) else { return nil }
        let own = (links[.lecture] ?? []) + (links[.classNote] ?? [])
        return layout.links.contains(where: own.contains) ? layout : nil
    }

    public func layout(session: Session?, course: UUID?) -> PaneLayout? {
        let links = if let session, let course { Self.links(session: session, course: course) } else { [Role: [AppLink]]() }
        if needsClass, links.isEmpty { return nil }
        return layout(links, focus: focus, spreads: false)
    }

    public func matches(_ layout: PaneLayout, session: Session?, course: UUID?) -> Bool {
        guard let filled = self.layout(session: session, course: course) else { return false }
        return filled.links.map(\.withoutAnchor) == layout.links.map(\.withoutAnchor)
    }

    public static func matching(_ layout: PaneLayout, among presets: [PanePreset], in file: CourseFile?) -> PanePreset? {
        presets.first { preset in
            guard preset.needsClass else { return preset.matches(layout, session: nil, course: nil) }
            guard let file else { return false }
            return file.sessions.contains { preset.matches(layout, session: $0, course: file.course.id) }
        }
    }

    public static func matching(_ layout: PaneLayout, session: Session, course: UUID) -> PanePreset? {
        builtIn.first { $0.matches(layout, session: session, course: course) }
    }

    public static func saving(_ layout: PaneLayout, name: String, session: Session?, course: UUID?) -> PanePreset {
        let links = if let session, let course { Self.links(session: session, course: course) } else { [Role: [AppLink]]() }
        let order: [Role] = [.classNote, .reviewNote, .lecture, .quiz]
        let slots: [Slot] = layout.panes.map { pane in
            let role = order.first { role in (links[role] ?? []).contains { $0.withoutAnchor == pane.link.withoutAnchor } }
            return role.map(Slot.role) ?? .link(pane.link)
        }
        return PanePreset(name: name, slots: slots, shares: layout.shares)
    }

    public static func freeName(_ base: String, taken: [String]) -> String {
        let names = Set(taken)
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

extension PanePreset.Slot: Codable {
    private enum Keys: String, CodingKey { case role, link }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let role = try c.decodeIfPresent(PanePreset.Role.self, forKey: .role) {
            self = .role(role)
            return
        }
        let text = try c.decode(String.self, forKey: .link)
        guard let link = AppLink(string: text) else {
            throw DecodingError.dataCorruptedError(forKey: .link, in: c, debugDescription: "Not a folio link: \(text)")
        }
        self = .link(link)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .role(let role): try c.encode(role, forKey: .role)
        case .link(let link): try c.encode(link.string, forKey: .link)
        }
    }
}

extension PanePreset: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, panes, shares }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let slots = try c.decode([Slot].self, forKey: .panes)
        let shares = try c.decode([Double].self, forKey: .shares)
        guard !slots.isEmpty, shares.count == slots.count, shares.allSatisfy({ $0 > 0 && $0.isFinite }) else {
            throw DecodingError.dataCorruptedError(forKey: .shares, in: c, debugDescription: "A share for each pane, each positive")
        }
        self.init(
            id: try c.decode(String.self, forKey: .id), name: try c.decodeIfPresent(String.self, forKey: .name), slots: slots,
            shares: shares)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(slots, forKey: .panes)
        try c.encode(shares, forKey: .shares)
    }
}

extension PaneLayout {
    public func lesson(in files: [CourseFile], now: Date) -> (course: UUID, session: Session)? {
        if let id = session(in: files) {
            for file in files { if let s = file.sessions.first(where: { $0.id == id }) { return (file.course.id, s) } }
        }

        let order = [focus] + panes.indices.filter { $0 != focus }
        for i in order {
            let link = panes[i].link
            guard link.kind == .material, let material = link.id else { continue }
            for file in files {
                let given = file.sessions.filter { $0.kind != .cancelled && $0.materials.contains { $0.materialId == material } }
                    .sorted { $0.date < $1.date }
                if let s = given.last(where: { $0.date <= now }) ?? given.first { return (file.course.id, s) }
            }
        }
        return nil
    }
}
