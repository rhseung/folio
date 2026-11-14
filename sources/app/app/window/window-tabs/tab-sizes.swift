import FolioDomain
import SwiftUI

@MainActor final class TabSizes {
    var trail: CGFloat = 0
    var front: CGFloat = 0
    var compactFront: CGFloat = 0
    var more: CGFloat = 0
    private var others: [UUID: [TabForm: CGFloat]] = [:]

    var frontFit: TabFit.Front {
        TabFit.Front(trail: Double(trail), chrome: Double(front - trail), compactChrome: Double(compactFront - trail))
    }

    func set(_ width: CGFloat, _ id: UUID, _ form: TabForm) { others[id, default: [:]][form] = width }

    func other(_ id: UUID) -> TabFit.Other {
        let widths = others[id] ?? [:]
        let icon = TabBar.icon
        return TabFit.Other(
            full: Double(widths[.full] ?? icon), icons: Double(widths[.icons] ?? icon), stacked: Double(widths[.stacked] ?? icon))
    }

    func keep(_ ids: Set<UUID>) { others = others.filter { ids.contains($0.key) } }
}
