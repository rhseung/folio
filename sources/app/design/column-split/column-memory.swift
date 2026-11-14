import SwiftUI

@MainActor final class ColumnMemory {
    // 테스트 호스트, 창 스냅숏 실행, 크기 측정 실행은 설치된 앱과 bundle ID가 같아서 defaults도 사용자의 것을 쓴다.
    // 그러면 사용자가 숨긴 열이 측정이나 그림을 바꾸고, 실행이 숨긴 열은 사용자에게 계속 숨겨진다.
    static let shared = ColumnMemory(defaults: isolated ? nil : .standard)
    private static var isolated: Bool {
        #if DEBUG && os(macOS)
        if SnapshotDriver.directory != nil { return true }
        #endif
        #if os(macOS) && (DEBUG || RESIZE_PROBE)
        if ResizeProbe.file != nil { return true }
        #endif
        return LocalFolders.isIsolated()
    }
    private let defaults: UserDefaults?
    private(set) var last: Set<ColumnKind>

    init(defaults: UserDefaults?, collapsed: Set<ColumnKind> = []) {
        self.defaults = defaults
        last = defaults.map { d in Set(ColumnKind.allCases.filter { d.bool(forKey: Self.key($0)) }) } ?? collapsed
    }

    static func key(_ kind: ColumnKind) -> String { "columnCollapsed.\(kind.rawValue)" }

    func remember(_ kind: ColumnKind, collapsed on: Bool) {
        if on { last.insert(kind) } else { last.remove(kind) }
        defaults?.set(on, forKey: Self.key(kind))
    }

    func newPane() -> ColumnPrefs { ColumnPrefs(collapsed: last, memory: self) }

    // 나중 빌드가 없앤 종류가 있어도 요청 전체와 창이 실패하지 않도록, 원래 이름으로 받아 모르는 종류만 건너뛴다.
    func pane(_ kinds: [String]?) -> ColumnPrefs {
        guard let kinds else { return newPane() }
        return ColumnPrefs(collapsed: Set(kinds.compactMap(ColumnKind.init(rawValue:))), memory: self)
    }
}
