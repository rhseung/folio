import CoreGraphics
import Testing

@testable import Folio

struct WindowSizeTests {
    // 보이는 영역은 기본 배율에서 Dock을 숨긴 14인치 MacBook Pro, 1920x1080 디스플레이, 메뉴 막대를 뺀 1280x800의 13인치 노트북이다.
    @Test func opensAtAShareOfTheScreen() {
        #expect(WindowSize.opening(in: CGSize(width: 1512, height: 949)) == CGSize(width: 1360, height: 852))
        #expect(WindowSize.opening(in: CGSize(width: 1920, height: 1050)) == CGSize(width: 1440, height: 900))
        #expect(WindowSize.opening(in: CGSize(width: 1280, height: 767)) == CGSize(width: 1152, height: 688))
    }

    @Test func theMinimumFitsASmallLaptop() {
        #expect(Theme.Size.windowMin.width <= 1280 && Theme.Size.windowMin.height <= 767)
    }

    // 내용의 최소 frame이 창을 이 크기 이상으로 유지하므로, 더 작게 요청하면 혼란만 준다.
    @Test func aScreenUnderTheMinimumGetsTheMinimum() {
        #expect(WindowSize.opening(in: CGSize(width: 1024, height: 600)) == Theme.Size.windowMin)
    }

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

    @Test func leavesRoomForTheDock() {
        #expect(WindowSize.opening(in: CGSize(width: 1512, height: 877)) == CGSize(width: 1360, height: 788))
    }
}
