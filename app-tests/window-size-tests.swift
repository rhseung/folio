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

    @Test func aScreenUnderTheMinimumIsFilled() {
        #expect(WindowSize.opening(in: CGSize(width: 1024, height: 600)) == CGSize(width: 1024, height: 600))
    }

    // The bug this guards: the old fixed 1520pt default was wider than a 1512pt screen.
    @Test func neverOpensPastTheScreenNorUnderTheMinimum() {
        for width in stride(from: 800, through: 3200, by: 7) {
            for height in stride(from: 500, through: 2000, by: 11) {
                let room = CGSize(width: width, height: height)
                let size = WindowSize.opening(in: room)
                #expect(size.width <= room.width && size.height <= room.height)
                #expect(size.width <= Theme.Size.windowIdeal.width && size.height <= Theme.Size.windowIdeal.height)
                #expect(size.width >= min(Theme.Size.windowMin.width, room.width))
                #expect(size.height >= min(Theme.Size.windowMin.height, room.height))
            }
        }
    }

    // The same laptop with the Dock shown at the bottom.
    @Test func leavesRoomForTheDock() {
        #expect(WindowSize.opening(in: CGSize(width: 1512, height: 877)) == CGSize(width: 1360, height: 788))
    }
}
