import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct DiagnosticStoreTests {
    let store = DiagnosticStore(url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    func record(at seconds: TimeInterval) -> DiagnosticRecord {
        let date = Date(timeIntervalSince1970: seconds)
        return DiagnosticRecord(
            source: .diagnostic, received: date, span: DateInterval(start: date, duration: 0),
            payload: ["hangDiagnostics": [["diagnosticMetaData": ["hangDuration": "2 sec"]]]])
    }

    @Test func recordsComeBackNewestFirst() throws {
        #expect(store.all().isEmpty)
        let old = record(at: 1_794_000_000), new = record(at: 1_794_100_000)
        try store.add([old])
        try store.add([new])
        #expect(store.all().map(\.id) == [new.id, old.id])
        #expect(store.all().first?.events.first?.detail == "2 sec")
    }

    @Test func aBrokenFileDoesNotHideTheRest() throws {
        let kept = record(at: 1_794_000_000)
        try store.add([kept])
        try Data("{".utf8).write(to: store.url.appending(path: "report-broken.json"))
        #expect(store.all().map(\.id) == [kept.id])
    }

    @Test func seenSurvivesRemovingTheReports() throws {
        #expect(store.seenThrough == nil)
        try store.add([record(at: 1_794_000_000)])
        try store.markSeen(through: Date(timeIntervalSince1970: 1_794_000_000))
        try store.removeAll()
        #expect(store.all().isEmpty)
        #expect(store.seenThrough == Date(timeIntervalSince1970: 1_794_000_000))
    }
}
