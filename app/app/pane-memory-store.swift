import FolioDomain
import Foundation
import SwiftUI

/// This device's `PaneMemory`, kept in its defaults rather than the GIST folder (see `PaneMemory`). Tests and
/// previews get none, so they neither read nor change what the app remembers.
@MainActor final class PaneMemoryStore {
    static let key = "paneMemory"

    private let defaults: UserDefaults
    private(set) var memory: PaneMemory

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Unreadable (a newer build's shape, say) is the same as nothing remembered: it only costs the defaults.
        memory = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(PaneMemory.self, from: $0) } ?? PaneMemory()
    }

    func remember(_ mode: NoteViewMode, note: UUID) {
        guard memory.noteMode(note: note) != mode else { return }
        memory.remember(mode, note: note, at: .now)
        save()
    }

    /// Opening a note uses what is remembered of it, so a note opened often outlasts `PaneMemory.capacity` though its
    /// mode was set long ago.
    func touch(note: UUID) {
        guard let mode = memory.noteMode(note: note) else { return }
        memory.remember(mode, note: note, at: .now)
        save()
    }

    func remember(_ layout: PaneLayout, session: UUID) {
        memory.remember(layout, session: session, at: .now)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: Self.key) }
    }
}

extension EnvironmentValues {
    @Entry var paneMemory: PaneMemoryStore? = nil
}
