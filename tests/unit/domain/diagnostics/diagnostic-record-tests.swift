import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct DiagnosticRecordTests {
    static let end = Date(timeIntervalSince1970: 1_794_800_000)
    static let span = DateInterval(start: end.addingTimeInterval(-60), end: end)

    // MetricKit의 `MXDiagnosticPayload.jsonRepresentation()`과 같은 꼴이다.
    static let diagnostic = Data(
        #"""
        {
          "timeStampBegin": "2026-11-15 10:00:00",
          "timeStampEnd": "2026-11-15 10:01:00",
          "crashDiagnostics": [
            {
              "version": "1.0.0",
              "callStackTree": {
                "callStackPerThread": true,
                "callStacks": [{"threadAttributed": true, "callStackRootFrames": [
                  {"binaryName": "Folio", "binaryUUID": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "address": 4295000000,
                   "offsetIntoBinaryTextSegment": 123456, "sampleCount": 1, "subFrames": []}
                ]}]
              },
              "diagnosticMetaData": {
                "appVersion": "0.4.0", "appBuildVersion": "12", "osVersion": "macOS 26.1 (25B78)", "deviceType": "Mac15,6",
                "exceptionType": 1, "exceptionCode": 0, "signal": 11,
                "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
                "virtualMemoryRegionInfo": "0 is not in any region.\nmapped file /Users/me/GIST/2026-3/EC4207 그래프 이론/Lectures/05_Matchings.pdf"
              }
            },
            {
              "callStackTree": {"callStackPerThread": true, "callStacks": []},
              "diagnosticMetaData": {
                "appVersion": "0.4.0", "exceptionType": 10, "signal": 6,
                "objectiveCexceptionReason": {
                  "composedMessage": "*** -[NSFileManager copyItemAtPath:] /Users/me/GIST/2026-3/EC4207 그래프 이론/Notes/a.md",
                  "formatString": "*** -[%@ %@] %@", "arguments": ["NSFileManager", "copyItemAtPath:", "EC4207 그래프 이론"],
                  "exceptionType": "NSException", "className": "NSException", "exceptionName": "NSInvalidArgumentException"
                }
              }
            }
          ],
          "hangDiagnostics": [
            {"callStackTree": {"callStackPerThread": false, "callStacks": []},
             "diagnosticMetaData": {"appVersion": "0.4.0", "hangDuration": "3.2 sec"}}
          ],
          "cpuExceptionDiagnostics": [
            {"callStackTree": {"callStackPerThread": false, "callStacks": []},
             "diagnosticMetaData": {"appVersion": "0.4.0", "totalCPUTime": "92 sec", "totalSampledTime": "180 sec"}}
          ],
          "diskWriteExceptionDiagnostics": [
            {"callStackTree": {"callStackPerThread": false, "callStacks": []},
             "diagnosticMetaData": {"appVersion": "0.4.0", "writesCaused": "2,048 MB"}}
          ]
        }
        """#.utf8)

    static let metric = Data(
        #"""
        {
          "appVersion": "0.4.0",
          "metaData": {"appVersion": "0.4.0", "appBuildVersion": "12"},
          "memoryMetrics": {"peakMemoryUsage": "2,800,000 kB"},
          "applicationExitMetrics": {
            "foregroundExitData": {"cumulativeMemoryResourceLimitExitCount": 2, "cumulativeNormalAppExitCount": 4},
            "backgroundExitData": {"cumulativeMemoryResourceLimitExitCount": 1}
          }
        }
        """#.utf8)

    func record(_ json: Data, source: DiagnosticRecord.Source = .diagnostic) throws -> DiagnosticRecord {
        try DiagnosticRecord(source: source, received: Self.end, span: Self.span, json: json)
    }

    @Test func aDiagnosticPayloadListsEachCrashHangAndException() throws {
        let events = try record(Self.diagnostic).events
        #expect(events.map(\.kind) == [.crash, .crash, .hang, .cpu, .diskWrite])
        #expect(events.map(\.detail) == ["EXC_BAD_ACCESS · SIGSEGV", "NSInvalidArgumentException", "3.2 sec", "92 sec", "2,048 MB"])
        #expect(events.allSatisfy { $0.appVersion == "0.4.0" && $0.date == Self.end && $0.count == 1 })
    }

    @Test func aCrashWithoutNumbersFallsBackToTheTerminationReason() throws {
        let json = Data(#"{"crashDiagnostics": [{"diagnosticMetaData": {"terminationReason": "Namespace RUNNINGBOARD"}}]}"#.utf8)
        #expect(try record(json).events.map(\.detail) == ["Namespace RUNNINGBOARD"])
        let unknown = Data(#"{"crashDiagnostics": [{"diagnosticMetaData": {"exceptionType": 99}}]}"#.utf8)
        #expect(try record(unknown).events.map(\.detail) == ["EXC 99"])
        let huge = Data(#"{"hangDiagnostics": [{"diagnosticMetaData": {"hangDuration": 1e20, "appVersion": 2.5}}]}"#.utf8)
        #expect(try record(huge).events.map(\.detail) == ["1e+20"])
        #expect(try record(huge).events.map(\.appVersion) == ["2.5"])
    }

    @Test func memoryLimitExitsBecomeOneMemoryEvent() throws {
        let events = try record(Self.metric, source: .metric).events
        #expect(events == [DiagnosticEvent(kind: .memory, date: Self.end, appVersion: "0.4.0", detail: "2,800,000 kB", count: 3)])
        let calm = Data(#"{"applicationExitMetrics": {"foregroundExitData": {"cumulativeMemoryResourceLimitExitCount": 0}}}"#.utf8)
        #expect(try record(calm, source: .metric).events.isEmpty)
    }

    @Test func pathsAndExceptionMessagesAreRemoved() throws {
        let stored = try DiagnosticExport.encoder.encode(try record(Self.diagnostic))
        let text = try #require(String(bytes: stored, encoding: .utf8))
        for secret in ["GIST", "그래프 이론", "05_Matchings", "/Users/me", "copyItemAtPath:]"] { #expect(!text.contains(secret), "\(secret)") }
        #expect(text.contains("0 is not in any region.\\nmapped file <path>"))
        #expect(text.contains("NSInvalidArgumentException"))
        #expect(text.contains("*** -[%@ %@] %@"))
        #expect(text.contains("Folio"))
    }

    @Test func redactionKeepsWordsThatOnlyHaveASlash() {
        #expect(DiagnosticRedaction.redact("1/2 done and/or not") == "1/2 done and/or not")
        #expect(DiagnosticRedaction.redact("open '/tmp/x y.md' failed\nnext") == "open '<path>\nnext")
        #expect(DiagnosticRedaction.redact("url=file:///Users/me/a b") == "url=<path>")
        #expect(DiagnosticRedaction.redact("~/GIST/x") == "<path>")
        #expect(DiagnosticRedaction.redact("a / b") == "a / b")
    }

    @Test func redactionLeavesNoPathBehind() async {
        // 경로 뒤의 글은 띄어쓰기와 문장부호가 섞인 과목 이름일 수 있다. 그 줄은 어떤 글이 와도 남지 않아야 한다.
        let rest = Gen.oneOf(Gen.character(in: "가"..."힣"), Gen.character(in: " "..."~")).string(of: 0...24)
        let start = Gen.oneOf(Gen.character(in: "가"..."힣"), Gen.character(in: "a"..."z")).string(of: 1...8)
        let lead = Gen.element(of: ["", "open ", "x='", "path=", "("]).map { $0 ?? "" }
        await propertyCheck(input: lead, start, rest) { lead, start, rest in
            #expect(DiagnosticRedaction.redact("\(lead)/\(start)\(rest)\nnext") == "\(lead)<path>\nnext")
        }
    }

    @Test func anExportRoundTripsAndSortsByTime() throws {
        let later = try DiagnosticRecord(
            source: .metric, received: Self.end, span: DateInterval(start: Self.end, duration: 86_400), json: Self.metric)
        let earlier = try record(Self.diagnostic)
        let export = DiagnosticExport(exported: Self.end, appVersion: "0.4.0", records: [later, earlier])
        #expect(export.records.map(\.id) == [earlier.id, later.id])
        let read = try DiagnosticExport.decoder.decode(DiagnosticExport.self, from: try export.data())
        #expect(read.records.map(\.events) == export.records.map(\.events))
        #expect(read.schemaVersion == 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        #expect(DiagnosticExport.fileName(at: Self.end, calendar: calendar) == "folio-diagnostics-2026-11-16.json")
    }
}
