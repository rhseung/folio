import Foundation

/// A named layout to switch to (#62, #64): what goes in each pane, and how wide. The built-in ones are here; the
/// ones the user saves ("지금 배치 저장…", 2026-11-11 사용자) live in settings.json (`Settings.panePresets`), since
/// the user names and orders them, unlike the device's remembered layouts (`PaneMemory`). The app names the built-in
/// ones from its string catalog by `id`.
public struct PanePreset: Hashable, Sendable, Identifiable {
    /// A pane filled from a class: the class's own page of that kind.
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// The session's lecture file, at its first page.
        case lecture
        /// The note written in class.
        case classNote
        case reviewNote
        /// The course's quiz. No built-in layout has it while the quiz is unproven in use (2026-11-11 사용자), but a
        /// saved tab with the quiz keeps it as the class's.
        case quiz
    }

    /// A pane: a role a class fills in, or the same address whatever the class.
    public enum Slot: Hashable, Sendable {
        case role(Role)
        case link(AppLink)

        public var role: Role? {
            if case .role(let role) = self { role } else { nil }
        }
    }

    public var id: String
    /// The user's name for a layout they saved; nil for a built-in one.
    public var name: String?
    public var slots: [Slot]
    public var shares: [Double]
    /// The pane chosen first, a built-in layout's place to write. A saved layout starts on its first pane.
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
    /// The review note is written from the lecture and what was jotted in class (2026-11-11 사용자), not the quiz.
    public static let review = PanePreset(id: "review", roles: [.lecture, .classNote, .reviewNote], shares: [0.4, 0.3, 0.3], focus: .reviewNote)
    /// "개념 다지기" (lecture and quiz) and "문제 풀이" (problem sheet and canvas) are left out until the canvas exists
    /// and the quiz is in use (2026-11-11 사용자).
    public static let builtIn = [inClass, review]

    public var roles: [Role] { slots.compactMap(\.role) }
    public var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }
    /// A layout with a role has nothing to show in a tab that isn't a class's (2026-11-11 사용자): it is off there.
    public var needsClass: Bool { slots.contains { $0.role != nil } }

    /// Whether a class's start can open it: it has the class's lecture or note to open.
    public var opensClass: Bool { roles.contains(.lecture) || roles.contains(.classNote) }

    /// What each role is for a session: its lectures in order, its notes, the course's quiz.
    public static func links(session: Session, course: UUID) -> [Role: [AppLink]] {
        [.lecture: session.materials.map { AppLink(.material, $0.materialId, anchor: $0.firstPage.map(AppLink.Anchor.page)) },
         .classNote: session.roughNoteId.map { [AppLink(.note, $0)] } ?? [],
         .reviewNote: session.reviewNoteId.map { [AppLink(.note, $0)] } ?? [],
         .quiz: [.course(course, page: .quiz)]]
    }

    /// The preset filled with `links` for each role. A role in one slot takes all of its links there, sharing the
    /// slot's width (a class's lectures when it starts, #391, 2026-11-09 사용자), unless `spreads` is off; a role in
    /// several slots gives each the next link, the last slot taking the rest. Every slot given a link keeps one pane
    /// before a slot gets a second, so past `limit` a third lecture gives way, not the note, and a slot gives way from
    /// the end, `focus`'s last (an iPad's two panes of "복습" are the lecture and the review note). Focused on
    /// `focus`'s first pane, else the first pane. Nil without a link.
    public func layout(_ links: [Role: [AppLink]], focus: Role? = nil, limit: Int, spreads: Bool = true) -> PaneLayout? {
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
        var counts = filled.map { $0.isEmpty ? 0 : 1 }
        while counts.reduce(0, +) > max(1, limit),
              let last = counts.indices.last(where: { counts[$0] > 0 && (focus == nil || slots[$0].role != focus) }) ?? counts.lastIndex(where: { $0 > 0 }) {
            counts[last] = 0
        }
        for i in filled.indices {
            while counts[i] > 0, counts[i] < filled[i].count, counts.reduce(0, +) < limit { counts[i] += 1 }
        }
        var chosen: [AppLink] = []
        var widths: [Double] = []
        var focused: Int?
        for (i, (slot, share)) in zip(slots, shares).enumerated() where counts[i] > 0 {
            if let focus, slot.role == focus, focused == nil { focused = chosen.count }
            for link in filled[i].prefix(counts[i]) {
                chosen.append(link)
                widths.append(share / Double(counts[i]))
            }
        }
        guard var layout = PaneLayout(links: chosen, shares: widths, limit: limit) else { return nil }
        if let focused { layout.press(focused) }
        return layout
    }

    /// The preset filled for a class's start, focused on its note. Nil when none of the class's own lectures or note
    /// made it in: "개념 다지기" for a class with no lecture would open a tab of the quiz alone, and the note just made
    /// for the class would open nowhere. The class then opens the plain way.
    public func startLayout(_ links: [Role: [AppLink]], limit: Int) -> PaneLayout? {
        guard let layout = layout(links, focus: .classNote, limit: limit) else { return nil }
        let own = (links[.lecture] ?? []) + (links[.classNote] ?? [])
        return layout.links.contains(where: own.contains) ? layout : nil
    }

    /// The preset filled in for a session, a pane to a slot, without the slots it has nothing for. Nil when it has
    /// none, and for a preset with a role and no session.
    public func layout(session: Session?, course: UUID?, limit: Int) -> PaneLayout? {
        let links = if let session, let course { Self.links(session: session, course: course) } else { [Role: [AppLink]]() }
        if needsClass, links.isEmpty { return nil }
        return layout(links, focus: focus, limit: limit, spreads: false)
    }

    /// Whether `layout` is this preset filled in for the session, so a tab can go by the preset's name. Pages and
    /// blocks don't count, nor widths: a lecture read further on is still the same layout.
    public func matches(_ layout: PaneLayout, session: Session?, course: UUID?, limit: Int) -> Bool {
        guard let filled = self.layout(session: session, course: course, limit: limit) else { return false }
        return filled.links.map(\.withoutAnchor) == layout.links.map(\.withoutAnchor)
    }

    /// The first of `presets` the layout is, for any of `file`'s classes (or none, for a preset of addresses only).
    public static func matching(_ layout: PaneLayout, among presets: [PanePreset], in file: CourseFile?, limit: Int) -> PanePreset? {
        presets.first { preset in
            guard preset.needsClass else { return preset.matches(layout, session: nil, course: nil, limit: limit) }
            guard let file else { return false }
            return file.sessions.contains { preset.matches(layout, session: $0, course: file.course.id, limit: limit) }
        }
    }

    public static func matching(_ layout: PaneLayout, session: Session, course: UUID, limit: Int) -> PanePreset? {
        builtIn.first { $0.matches(layout, session: session, course: course, limit: limit) }
    }

    /// "지금 배치 저장…" (2026-11-11 사용자): each pane that is one of the class's own pages is kept as that role, so
    /// choosing the layout in another class's tab fills it with that class's, and a class's start can open it; any
    /// other pane is kept at its address.
    public static func saving(_ layout: PaneLayout, name: String, session: Session?, course: UUID?) -> PanePreset {
        let links = if let session, let course { Self.links(session: session, course: course) } else { [Role: [AppLink]]() }
        // Notes before the lecture: a class's note can't also be its lecture, but the order keeps that true by rule.
        let order: [Role] = [.classNote, .reviewNote, .lecture, .quiz]
        let slots: [Slot] = layout.panes.map { pane in
            let role = order.first { role in (links[role] ?? []).contains { $0.withoutAnchor == pane.link.withoutAnchor } }
            return role.map(Slot.role) ?? .link(pane.link)
        }
        return PanePreset(name: name, slots: slots, shares: layout.shares)
    }

    /// A name for a layout about to be saved that none of `taken` has: `기본` alone, then `기본 2`, `기본 3`.
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

    // Links are written as their `folio://` text, as `PaneLayout` writes them.
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
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decodeIfPresent(String.self, forKey: .name), slots: slots, shares: shares)
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
    /// The class a preset's roles are filled from in this layout's tab: the one its notes and recordings belong to
    /// (`session(in:)`), else the class a lecture shown here was last given in by `now` (the first to come, if none
    /// was yet), the focused pane's lecture first. Nil for a tab of no class's pages.
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
