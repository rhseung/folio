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
