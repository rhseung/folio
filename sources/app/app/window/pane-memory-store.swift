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
