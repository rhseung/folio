import FolioDomain
import SwiftUI

// SwiftUI는 같은 값을 보이는 창이 이미 있으면 새로 열지 않고 그 창을 앞으로 가져온다. 같은 링크를 두 번 요청하면 창이
// 두 개 열려야 하므로 요청마다 ID를 둔다.
struct WindowRequest: Codable, Hashable {
    var id = UUID()
    var link: AppLink
    var course: UUID?
    var history: LinkHistory<Navigator.Entry>?
    var panes: [LinkHistory<Navigator.Entry>]?
    var shares: [Double]?
    var focus: Int?
    var columns: [[String]]?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension WindowRequest {
    // 다른 창으로 옮기는 탭은 칸마다 기록과 폭, 초점, 열 설정을 함께 가져간다.
    @MainActor init(moving panes: TabPanes) {
        let focused = panes.focused
        self.init(link: focused.current.link, course: focused.current.course, history: focused.history)
        if panes.count > 1 {
            self.panes = panes.navigators.map(\.history)
            shares = panes.shares
            focus = panes.focus
        }
        columns = panes.columns.map(\.names)
    }
}
