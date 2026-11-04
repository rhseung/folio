import CoreGraphics
import Testing
@testable import Folio

struct WindowSizeTests {
    // Visible areas: a 14" MacBook Pro at its default scale with the Dock hidden, a 1920x1080 display, a 13" laptop at
    // 1280x800 less the menu bar.
    @Test func opensAtAShareOfTheScreen() {
        #expect(WindowSize.opening(in: CGSize(width: 1512, height: 949)) == CGSize(width: 1360, height: 852))
        #expect(WindowSize.opening(in: CGSize(width: 1920, height: 1050)) == CGSize(width: 1440, height: 900))
        #expect(WindowSize.opening(in: CGSize(width: 1280, height: 767)) == CGSize(width: 1152, height: 688))
    }

    @Test func theMinimumFitsASmallLaptop() {
        #expect(Theme.Size.windowMin.width <= 1280 && Theme.Size.windowMin.height <= 767)
    }

    // The content's minimum frame keeps the window at least this big, so asking for less would only mislead.
    @Test func aScreenUnderTheMinimumGetsTheMinimum() {
        #expect(WindowSize.opening(in: CGSize(width: 1024, height: 600)) == Theme.Size.windowMin)
    }

    // The bug this guards: the old fixed 1520pt default was wider than a 1512pt screen.
    @Test func neverOpensPastAScreenThatHoldsTheMinimumNorUnderIt() {
        for width in stride(from: 800, through: 3200, by: 7) {
            for height in stride(from: 500, through: 2000, by: 11) {
                let room = CGSize(width: width, height: height)
                let size = WindowSize.opening(in: room)
                if room.width >= Theme.Size.windowMin.width { #expect(size.width <= room.width) }
                if room.height >= Theme.Size.windowMin.height { #expect(size.height <= room.height) }
                #expect(size.width <= Theme.Size.windowIdeal.width && size.height <= Theme.Size.windowIdeal.height)
                #expect(size.width >= Theme.Size.windowMin.width && size.height >= Theme.Size.windowMin.height)
            }
        }
    }

    // The same laptop with the Dock shown at the bottom.
    @Test func leavesRoomForTheDock() {
        #expect(WindowSize.opening(in: CGSize(width: 1512, height: 877)) == CGSize(width: 1360, height: 788))
    }
}
