import SwiftUI

@MainActor @Observable final class ColumnPrefs {
    private(set) var collapsed: Set<ColumnKind>
    @ObservationIgnored private let memory: ColumnMemory?

    // 렌더와 테스트가 새 칸의 시작 상태를 바꾸면 안 되므로, 기억할 곳이 없으면 이 칸 안에서만 기억한다.
    init(collapsed: Set<ColumnKind> = [], memory: ColumnMemory? = nil) {
        self.collapsed = collapsed
        self.memory = memory
    }

    static let loose = ColumnMemory.shared.newPane()

    func isCollapsed(_ kind: ColumnKind) -> Bool { collapsed.contains(kind) }

    func set(_ kind: ColumnKind, collapsed on: Bool) {
        if on { collapsed.insert(kind) } else { collapsed.remove(kind) }
        memory?.remember(kind, collapsed: on)
    }
}

extension ColumnPrefs {
    var names: [String] { collapsed.map(\.rawValue).sorted() }
}
