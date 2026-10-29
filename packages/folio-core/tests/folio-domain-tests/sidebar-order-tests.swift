import FolioDomain
import Foundation
import Testing

struct SidebarOrderTests {
    // Readable stand-ins: id(1), id(2), ... in the default order.
    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    @Test func nothingStoredKeepsTheDefault() {
        #expect(SidebarOrder.arrange([id(1), id(2), id(3)], by: []) == [id(1), id(2), id(3)])
    }

    @Test func storedOrderWinsAndDropsWhatIsGone() {
        #expect(SidebarOrder.arrange([id(1), id(2), id(3)], by: [id(3), id(9), id(1), id(2), id(3)]) == [id(3), id(1), id(2)])
    }

    @Test func aNewCourseTakesItsDefaultPlace() {
        // Between two by name: in front of the first stored one that comes after it.
        #expect(SidebarOrder.arrange([id(1), id(2), id(3)], by: [id(3), id(1)]) == [id(2), id(3), id(1)])
        #expect(SidebarOrder.arrange([id(0), id(1), id(2)], by: [id(2), id(1)]) == [id(0), id(2), id(1)])
    }

    @Test func aCourseMovesWithinItsTerm() {
        let shown = [id(11), id(12), id(13)]
        var order = SidebarOrder(courses: [id(21), id(22)])
        order.move(shown, from: 0, to: 2)
        #expect(SidebarOrder.arrange(shown, by: order.courses) == [id(12), id(11), id(13)])
        // Another term's order is left as it was.
        #expect(SidebarOrder.arrange([id(22), id(21)], by: order.courses) == [id(21), id(22)])
        order.move([id(12), id(11), id(13)], from: 2, to: 0)
        #expect(SidebarOrder.arrange(shown, by: order.courses) == [id(13), id(12), id(11)])
        order.move([id(13), id(12), id(11)], from: 0, to: 3)
        #expect(SidebarOrder.arrange(shown, by: order.courses) == [id(12), id(11), id(13)])
    }

    @Test func oldSettingsFilesReadWithoutAnOrder() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"dayBoundaryMinutes": 240}"#.utf8))
        #expect(settings.sidebar == SidebarOrder())
    }
}
