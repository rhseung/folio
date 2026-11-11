import CryptoKit
import FolioDomain
import Foundation
import SwiftUI

/// This device's `PaneMemory`, kept in its defaults rather than the GIST folder (see `PaneMemory`). Tests and
/// previews get none, so they neither read nor change what the app remembers.
@MainActor final class PaneMemoryStore {
    static let key = "paneMemory"

    private let defaults: UserDefaults
    private let key: String
    private(set) var memory: PaneMemory

    init(defaults: UserDefaults, key: String = PaneMemoryStore.key) {
        self.defaults = defaults
        self.key = key
        // Unreadable (a newer build's shape, say) is the same as nothing remembered: it only costs the defaults.
        memory = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PaneMemory.self, from: $0) } ?? PaneMemory()
    }

    /// A run on a fixture (`FOLIO_GIST`, window snapshots included) keeps its own memory, apart from the user's: the
    /// debug app shares the installed app's defaults, and a fixture's classes would push the user's own out of
    /// `PaneMemory.capacity`. Per folder, so a fixture's layouts still come back when the app opens it again.
    static func forThisRun(environment: [String: String] = ProcessInfo.processInfo.environment) -> PaneMemoryStore {
        guard let gist = environment[Workspace.environmentKey], let fixtures = UserDefaults(suiteName: "folio-fixtures") else {
            return PaneMemoryStore(defaults: .standard)
        }
        let digest = SHA256.hash(data: Data(gist.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return PaneMemoryStore(defaults: fixtures, key: "\(key).\(digest)")
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
        guard memory.layout(session: session) != layout else { return }
        memory.remember(layout, session: session, at: .now)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: key) }
    }
}

extension EnvironmentValues {
    @Entry var paneMemory: PaneMemoryStore? = nil
    /// The pane a screen is drawn in, for a note to keep how it is shown in the tab's layout.
    @Entry var paneNotes: PaneNotes?
}

/// One pane's say in how its note is shown, kept in the tab's layout so the class's layout brings it back as it was
/// left (`PaneLayout.Pane.noteMode`).
struct PaneNotes: Equatable {
    let panes: TabPanes
    let pane: UUID

    // By identity, so the row handing out a new one each time it draws doesn't redraw every note in it.
    static func == (a: PaneNotes, b: PaneNotes) -> Bool { a.panes === b.panes && a.pane == b.pane }

    @MainActor func mode(of item: UUID) -> NoteViewMode? { panes.noteMode(of: item, pane: pane) }

    @MainActor func show(_ mode: NoteViewMode, of item: UUID) { panes.show(mode, of: item, pane: pane) }
}

/// Remembers a tab's layout as its class's whenever it changes, on this device (#62): a tab whose notes and
/// recordings are one class's (`PaneLayout.session(in:)`). Not a tab of one pane: a note reached by back, or in a
/// tab opened before the layout was, would put the class's layout out of memory. Its own view beside the panes, so
/// what it watches (every pane's address) redraws it alone.
struct SessionLayoutSaver: View {
    let workspace: Workspace
    let panes: TabPanes
    @Environment(\.paneMemory) private var memory

    /// What a remembered layout holds. Pages are in the links, so a lecture read on is remembered at its page.
    private struct Shape: Equatable {
        var links: [AppLink]
        var shares: [Double]
        var focus: Int
        var collapsed: Set<Int>
        var modes: [NoteViewMode?]
    }

    var body: some View {
        let shape = Shape(links: panes.navigators.map(\.current.link), shares: panes.shares, focus: panes.focus,
                          collapsed: panes.collapsed, modes: panes.noteModes)
        Color.clear
            .task(id: shape) {
                // A moment after the last change: turning through a lecture's pages writes once, not every page.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let memory, panes.count > 1 else { return }
                let layout = panes.current
                let files = Set(panes.navigators.compactMap(\.current.course)).compactMap { workspace.course($0)?.file }
                if let session = layout.session(in: files) { memory.remember(layout, session: session) }
            }
            .accessibilityHidden(true)
    }
}
