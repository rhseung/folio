import FolioDomain
import SwiftUI

// 나누기에서 빠지는 탭(오늘, 칸이 여럿인 안 고른 탭)과 더 보기 메뉴는 그려진 폭을 잰다.
@MainActor final class TabSizes {
    var front: CGFloat = 0
    var more: CGFloat = 0
    private var others: [UUID: CGFloat] = [:]

    func set(_ width: CGFloat, _ id: UUID) { others[id] = width }

    func other(_ id: UUID) -> CGFloat { others[id] ?? TabBar.icon }

    func keep(_ ids: Set<UUID>) { others = others.filter { ids.contains($0.key) } }
}
