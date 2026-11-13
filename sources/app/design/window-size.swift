import CoreGraphics

/// `visible` is the screen less the menu bar and Dock.
enum WindowSize {
    static func opening(in visible: CGSize) -> CGSize {
        CGSize(
            width: side(ideal: Theme.Size.windowIdeal.width, least: Theme.Size.windowMin.width, room: visible.width),
            height: side(ideal: Theme.Size.windowIdeal.height, least: Theme.Size.windowMin.height, room: visible.height))
    }

    // Down to the 4pt grid, then never under the minimum, even on a screen smaller than it: the content's own minimum
    // frame would win over a smaller ask anyway.
    private static func side(ideal: CGFloat, least: CGFloat, room: CGFloat) -> CGFloat {
        let share = (room * Theme.Size.windowShare / 4).rounded(.down) * 4
        return max(min(ideal, share), least)
    }
}
