import CoreGraphics

/// A new Mac window's size, from the screen it opens on. `visible` is the screen less the menu bar and Dock.
enum WindowSize {
    static func opening(in visible: CGSize) -> CGSize {
        CGSize(width: side(ideal: Theme.Size.windowIdeal.width, least: Theme.Size.windowMin.width, room: visible.width),
               height: side(ideal: Theme.Size.windowIdeal.height, least: Theme.Size.windowMin.height, room: visible.height))
    }

    // Down to the 4pt grid, then never under the minimum, and never past the screen: on a screen smaller than the
    // minimum the window fills it rather than spilling over.
    private static func side(ideal: CGFloat, least: CGFloat, room: CGFloat) -> CGFloat {
        let share = (room * Theme.Size.windowShare / 4).rounded(.down) * 4
        return min(max(min(ideal, share), least), room)
    }
}
