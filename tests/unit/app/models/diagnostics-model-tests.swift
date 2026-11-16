import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct DiagnosticsModelTests {
    static let now = Date(timeIntervalSince1970: 1_794_800_000)

    func model() throws -> (DiagnosticsModel, DiagnosticStore) {
        let workspace = try fixtureWorkspace()
        workspace.pinnedNow = Self.now
        let store = DiagnosticStore(url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        workspace.diagnostics = DiagnosticLog(store: store)
        return (DiagnosticsModel(workspace: workspace), store)
    }

    func hang(at date: Date, seconds: String = "3.2 sec") -> DiagnosticRecord {
        DiagnosticRecord(
            source: .diagnostic, received: date, span: DateInterval(start: date, duration: 0),
            payload: ["hangDiagnostics": [["diagnosticMetaData": ["appVersion": "0.4.0", "hangDuration": .string(seconds)]]]])
    }

    @Test func aTestRunNeverReadsThisMacsReports() throws {
        #expect(DiagnosticLog.localStore == nil)
        #expect(try fixtureWorkspace().diagnostics.records.isEmpty)
    }

    @Test func newReportsRaiseTheNoticeUntilSeen() throws {
        let (model, _) = try model()
        #expect(model.newCount == 0)
        #expect(model.isEmpty)
        model.log.receive([hang(at: Self.now)])
        #expect(model.newCount == 1)
        #expect(model.noticeDetail == DiagnosticEvent.Kind.hang.label)
        #expect(model.rows.map(\.isNew) == [true])
        #expect(model.rows.first?.detail == "3.2 sec · " + String(localized: .diagnosticsVersion("0.4.0")))
        model.markSeen()
        #expect(model.newCount == 0)
        #expect(model.rows.map(\.isNew) == [false])
        model.log.receive([hang(at: Self.now.addingTimeInterval(60))])
        #expect(model.newCount == 1)
    }

    @Test func payloadsWithoutAnEventAreNotKept() throws {
        let (model, store) = try model()
        model.log.receive([
            DiagnosticRecord(
                source: .metric, received: Self.now, span: DateInterval(start: Self.now, duration: 86_400),
                payload: ["memoryMetrics": ["peakMemoryUsage": "100 kB"]])
        ])
        #expect(store.all().isEmpty)
        #expect(model.newCount == 0)
    }

    @Test func exportingTakesEveryReportAndMarksThemSeen() throws {
        let (model, _) = try model()
        model.log.receive((0..<25).map { hang(at: Self.now.addingTimeInterval(Double($0) * 60)) })
        #expect(model.rows.count == DiagnosticsModel.rowLimit)
        #expect(model.note != nil)
        model.export()
        let file = try #require(model.exporting)
        let read = try DiagnosticExport.decoder.decode(DiagnosticExport.self, from: file.data)
        #expect(read.records.count == 25)
        model.exported()
        #expect(model.exporting == nil)
        #expect(model.newCount == 0)
        #expect(model.exportName.hasPrefix("folio-diagnostics-"))
    }

    @Test func removingAllKeepsOldReportsFromComingBackAsNew() throws {
        let (model, store) = try model()
        model.log.receive([hang(at: Self.now)])
        model.removeAll()
        #expect(model.isEmpty)
        #expect(store.seenThrough != nil)
        #expect(model.newCount == 0)
    }
}
