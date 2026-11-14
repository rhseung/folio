import CoreGraphics

enum WindowSize {
    static func opening(in visible: CGSize) -> CGSize {
        CGSize(
            width: side(ideal: Theme.Size.windowIdeal.width, least: Theme.Size.windowMin.width, room: visible.width),
            height: side(ideal: Theme.Size.windowIdeal.height, least: Theme.Size.windowMin.height, room: visible.height))
    }

    private static func side(ideal: CGFloat, least: CGFloat, room: CGFloat) -> CGFloat {
        let share = (room * Theme.Size.windowShare / 4).rounded(.down) * 4
        return max(min(ideal, share), least)
    }
}
