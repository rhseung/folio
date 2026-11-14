import CryptoKit
import FolioDomain
import Foundation
import SwiftUI

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
