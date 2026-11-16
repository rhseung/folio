import Foundation

private extension PaneLayout {
    var nilIfAlone: PaneLayout? { panes.count > 1 ? self : nil }
}

public struct PaneMemory: Codable, Hashable, Sendable {
    public static let capacity = 300

    private struct Kept<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        var value: Value
        var used: Date
    }

    // UUID 키를 쓰면 Codable이 키와 값이 번갈아 놓인 배열로 쓰므로, 문자열 키를 써서 JSON 객체로 둔다.
    private var layouts: [String: Kept<PaneLayout>] = [:]
    private var noteModes: [String: Kept<NoteViewMode>] = [:]

    public init() {}

    public func layout(session: UUID) -> PaneLayout? { layouts[session.uuidString]?.value }

    public mutating func remember(_ layout: PaneLayout, session: UUID, at date: Date) {
        layouts[session.uuidString] = Kept(value: layout, used: date)
        Self.trim(&layouts)
    }

    public func restoring(_ link: AppLink, session: UUID) -> PaneLayout? {
        guard var saved = layout(session: session),
            let i = saved.panes.firstIndex(where: { $0.link.withoutAnchor == link.withoutAnchor })
        else { return nil }
        saved.open(link, in: i)
        saved.press(i)
        return saved.nilIfAlone
    }

    public func starting(session: UUID) -> PaneLayout? {
        layout(session: session)?.nilIfAlone
    }

    public func noteMode(note: UUID, session: UUID? = nil) -> NoteViewMode? {
        if let session, let layout = layout(session: session),
            let pane = layout.panes.first(where: { $0.link.id == note }), let mode = pane.noteMode
        {
            return mode
        }
        return noteModes[note.uuidString]?.value
    }

    public mutating func remember(_ mode: NoteViewMode, note: UUID, at date: Date) {
        noteModes[note.uuidString] = Kept(value: mode, used: date)
        Self.trim(&noteModes)
    }

    public var count: (layouts: Int, noteModes: Int) { (layouts.count, noteModes.count) }

    private static func trim<V>(_ kept: inout [String: Kept<V>]) {
        guard kept.count > capacity else { return }
        for key in kept.sorted(by: { ($0.value.used, $0.key) < ($1.value.used, $1.key) }).prefix(kept.count - capacity).map(\.key) {
            kept[key] = nil
        }
    }
}
