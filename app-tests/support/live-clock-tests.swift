import Foundation
import Observation
import Synchronization
import Testing
@testable import Folio

@MainActor
struct LiveClockTests {
    @Test func theNextTickIsTheNextMinuteBoundary() {
        let c = Calendar(identifier: .gregorian)
        func at(_ h: Int, _ m: Int, _ s: Double) -> Date {
            c.date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Seoul"), year: 2026, month: 11, day: 5, hour: h, minute: m))!
                .addingTimeInterval(s)
        }
        #expect(LiveClock.nextMinute(after: at(15, 56, 0)) == at(15, 57, 0))
        #expect(LiveClock.nextMinute(after: at(15, 59, 59.9)) == at(16, 0, 0))
        #expect(LiveClock.nextMinute(after: at(16, 0, 0.1)) == at(16, 1, 0))
    }

    /// What keeps the ribbon, the wash and the sidebar in step: each reads `liveNow` in its body, and a tick of the one
    /// clock redraws whatever read it.
    @Test func aTickRedrawsWhatReadTheLiveTime() throws {
        let workspace = try fixtureWorkspace()
        let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
        workspace.clock.refresh(at: start)
        #expect(workspace.liveNow == start)

        let redrawn = Mutex(false)
        withObservationTracking { _ = workspace.liveNow } onChange: { redrawn.withLock { $0 = true } }
        workspace.clock.refresh(at: start.addingTimeInterval(60))
        #expect(redrawn.withLock { $0 })
        #expect(workspace.liveNow == start.addingTimeInterval(60))
    }

    @Test func aPinnedTimeHoldsAgainstTheClock() throws {
        let workspace = try fixtureWorkspace()
        let pinned = Date(timeIntervalSinceReferenceDate: 815_000_000)
        workspace.pinnedNow = pinned
        workspace.clock.refresh(at: pinned.addingTimeInterval(3_600))
        #expect(workspace.liveNow == pinned)
        #expect(workspace.liveNow == workspace.now)
    }
}
