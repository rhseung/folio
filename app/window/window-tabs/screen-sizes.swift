import FolioDomain
import SwiftUI

@MainActor final class ScreenSizes {
    private var sizes: [UUID: CGSize] = [:]

    subscript(id: UUID) -> CGSize? {
        get { sizes[id] }
        set { sizes[id] = newValue }
    }

    func keep(_ ids: Set<UUID>) { sizes = sizes.filter { ids.contains($0.key) } }
}
