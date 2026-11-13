import FolioDomain
import Foundation
import PropertyBased
import Testing

/// What any deadline must keep, whatever the hour and the day boundary. The worked cases sit in CourseWorkTests.
struct DueUrgencyPropertyTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    static let boundary = Gen.int(in: 0...(8 * 60))
    static let offset = Gen.int(in: 0...(40 * 86_400))

    @Test func aLaterDeadlineIsNeverMoreUrgent() async {
        await propertyCheck(input: Self.boundary, Self.offset, Self.offset) { boundary, a, b in
            let settings = Settings(dayBoundaryMinutes: boundary)
            let now = start
            let (near, far) = (now.addingTimeInterval(Double(min(a, b))), now.addingTimeInterval(Double(max(a, b))))
            let urgency = { DueUrgency(due: $0, now: now, settings: settings, calendar: calendar) }
            #expect(urgency(near) <= urgency(far))
        }
    }

    @Test func anythingWithinADayIsUrgent() async {
        await propertyCheck(input: Self.boundary, Gen.int(in: 0...86_399)) { boundary, seconds in
            let settings = Settings(dayBoundaryMinutes: boundary)
            #expect(DueUrgency(due: start.addingTimeInterval(Double(seconds)), now: start, settings: settings, calendar: calendar) == .urgent)
        }
    }
}
