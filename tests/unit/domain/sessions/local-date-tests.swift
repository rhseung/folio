import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct LocalDateTests {
    static let calendars: [Calendar.Identifier] = [
        .gregorian, .hebrew, .islamic, .islamicUmmAlQura, .japanese, .buddhist, .persian, .chinese,
    ]

    static func calendar(_ id: Calendar.Identifier) -> Calendar {
        var c = Calendar(identifier: id)
        c.timeZone = TimeZone(secondsFromGMT: 9 * 3600) ?? .gmt
        return c
    }

    // 히브리력 5787년 아다르 2월(13월)과 이슬람력의 30일이 든 날이다.
    @Test(arguments: calendars) func aSystemCalendarStillReadsTheGregorianDay(id: Calendar.Identifier) throws {
        let seoul = Self.calendar(.gregorian)
        let day = try #require(seoul.date(from: DateComponents(year: 2027, month: 3, day: 20, hour: 23, minute: 30)))
        let local = try #require(LocalDate(year: 2027, month: 3, day: 20))
        #expect(LocalDate(day, in: Self.calendar(id)) == local)
        #expect(local.date(in: Self.calendar(id)) == seoul.startOfDay(for: day))
    }

    @Test func everyDayRoundTripsInEveryCalendar() async {
        await propertyCheck(input: Gen.int(in: -40_000...40_000), Gen.element(of: Self.calendars).map { $0 ?? .gregorian }) { days, id in
            let calendar = Self.calendar(id)
            let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(days) * 86_400)
            let local = LocalDate(date, in: calendar)
            #expect(local.date(in: calendar).map { LocalDate($0, in: calendar) } == local)
        }
    }
}
