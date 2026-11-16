import SwiftUI

enum TabDrop: Equatable {
    case strip(Int)
    case merge(WindowTabs.MergeDrop)
    case newTab
    case newWindow
    case none

    enum Item: Equatable {
        case tab(UUID)
        case pane(UUID, of: UUID)

        var tab: UUID {
            switch self {
            case .tab(let id), .pane(_, of: let id): id
            }
        }
    }

    // 받는 창의 모양이다. 자리는 모두 그 창의 global 좌표다.
    struct Area {
        var strip: CGRect
        var row: [UUID]
        var frames: [UUID: CGRect]
        var ids: [UUID]
        var selected: UUID
    }

    // 탭 줄의 위아래로 이만큼 벗어나도 아직 줄 안으로 본다. 줄에서 조금 미끄러진 손이 탭을 떼어 내지 않게 한다.
    static let reach = Theme.Space.l

    static func resolve(
        _ item: Item, at point: CGPoint, in area: Area?, merge: (CGPoint) -> WindowTabs.MergeDrop?, source: Bool,
        sourceTabs: Int, tears: Bool
    ) -> TabDrop {
        let pane: Bool = if case .pane = item { true } else { false }
        let away: TabDrop = tears && (pane || sourceTabs > 1) ? .newWindow : .none
        guard let area else { return away }
        if area.strip.minY - reach <= point.y, point.y <= area.strip.maxY + reach {
            // 칸 조각을 자기 탭 위에 도로 놓으면 아무것도 바꾸지 않는다.
            if source, pane, let own = area.frames[item.tab], own.minX <= point.x, point.x <= own.maxX { return .none }
            return .strip(index(at: point.x, in: area, moving: source && !pane ? item.tab : nil))
        }
        let mergeable = !source || (!pane && item.tab != area.selected)
        if mergeable, let drop = merge(point) { return .merge(drop) }
        if source, pane { return .newTab }
        return away
    }

    // 놓을 자리는 지금 보이는 탭의 가운데를 기준으로 고른다. 메뉴로 접힌 탭 사이로는 놓지 않는다.
    static func index(at x: CGFloat, in area: Area, moving: UUID?) -> Int {
        let others = area.row.filter { $0 != moving }
        let before = others.filter { (area.frames[$0]?.midX ?? 0) < x }.count
        let rest = area.ids.filter { $0 != moving }
        if before < others.count { return rest.firstIndex(of: others[before]) ?? 0 }
        return others.last.flatMap { rest.firstIndex(of: $0) }.map { $0 + 1 } ?? rest.count
    }

    // 다른 창에서 들어오는 탭이 설 자리를 가리키는 선의 x다.
    static func caret(at x: CGFloat, in area: Area, gap: CGFloat) -> CGFloat? {
        let frames = area.row.compactMap { area.frames[$0] }
        guard let last = frames.last else { return nil }
        let before = frames.filter { $0.midX < x }.count
        return before < frames.count ? frames[before].minX - gap / 2 : last.maxX + gap / 2
    }
}
