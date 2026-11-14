import CryptoKit
import FolioDomain
import Foundation
import SwiftUI

@MainActor final class PaneMemoryStore {
    static let key = "paneMemory"

    private let defaults: UserDefaults
    private let key: String
    private(set) var memory: PaneMemory

    init(defaults: UserDefaults, key: String = PaneMemoryStore.key) {
        self.defaults = defaults
        self.key = key
        memory = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PaneMemory.self, from: $0) } ?? PaneMemory()
    }

    // debug 앱은 설치한 앱과 defaults를 함께 쓰므로, 픽스처의 수업이 사용자의 수업을 `PaneMemory.capacity` 밖으로 밀어낸다.
    // 그래서 픽스처로 돌린 실행(`FOLIO_GIST`, 창 스냅숏 포함)은 따로 기억한다. 폴더마다 따로 두므로, 앱이 픽스처를 다시
    // 열면 그 배치가 돌아온다.
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

    #if DEBUG
    func forget() {
        memory = PaneMemory()
        save()
    }
    #endif

    private func save() {
        if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: key) }
    }
}

extension EnvironmentValues {
    @Entry var paneMemory: PaneMemoryStore? = nil
    @Entry var paneNotes: PaneNotes?
}

struct PaneNotes: Equatable {
    let panes: TabPanes
    let pane: UUID

    // 행이 그릴 때마다 새 값을 넘기므로, identity로 비교해야 그 안의 모든 노트가 다시 그려지지 않는다.
    static func == (a: PaneNotes, b: PaneNotes) -> Bool { a.panes === b.panes && a.pane == b.pane }

    @MainActor func mode(of item: UUID) -> NoteViewMode? { panes.noteMode(of: item, pane: pane) }

    @MainActor func show(_ mode: NoteViewMode, of item: UUID) { panes.show(mode, of: item, pane: pane) }
}

// 칸이 하나인 탭은 남기지 않는다. 뒤로 가서 연 노트나 배치를 남기기 전에 연 탭의 노트가 수업의 배치를 기억에서
// 밀어내기 때문이다.
struct SessionLayoutSaver: View {
    let workspace: Workspace
    let panes: TabPanes
    @Environment(\.paneMemory) private var memory

    private struct Shape: Equatable {
        var links: [AppLink]
        var shares: [Double]
        var focus: Int
        var collapsed: Set<Int>
        var modes: [NoteViewMode?]
    }

    var body: some View {
        let shape = Shape(
            links: panes.navigators.map(\.current.link), shares: panes.shares, focus: panes.focus,
            collapsed: panes.collapsed, modes: panes.noteModes)
        Color.clear
            .task(id: shape) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let memory, panes.count > 1 else { return }
                let layout = panes.current
                let files = Set(panes.navigators.compactMap(\.current.course)).compactMap { workspace.course($0)?.file }
                if let session = layout.session(in: files) { memory.remember(layout, session: session) }
            }
            .accessibilityHidden(true)
    }
}
