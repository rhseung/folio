import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import MetricKit
import Observation

// MetricKit은 크래시와 멈춤을 다음 실행에서 보낸다. 받은 보고는 이 기기에만 두고 바깥으로 보내지 않는다.
@MainActor @Observable
final class DiagnosticLog {
    private(set) var records: [DiagnosticRecord] = []
    private(set) var seenThrough: Date?
    @ObservationIgnored private let store: DiagnosticStore?
    @ObservationIgnored private var collector: Collector?

    // 테스트, 미리보기, 렌더는 저장소를 넘기지 않는 한 이 Mac의 보고를 읽지 않는다(`LocalFolders`). 픽스처로 돌린 앱(창
    // 스냅숏 포함)이 앱 정보 탭을 열면 사용자의 보고를 본 것으로 표시하므로, 그 실행은 자기 임시 폴더를 쓴다.
    init(store: DiagnosticStore? = DiagnosticLog.localStore) {
        self.store = store
        reload()
    }

    nonisolated static var localStore: DiagnosticStore? {
        LocalFolders.isIsolated() ? nil : DiagnosticStore(url: LocalFolders.applicationSupport("Diagnostics", perGIST: true))
    }

    func start() {
        guard store != nil, collector == nil else { return }
        let collector = Collector { [weak self] records in Task { @MainActor in self?.receive(records) } }
        MXMetricManager.shared.add(collector)
        self.collector = collector
    }

    func receive(_ new: [DiagnosticRecord]) {
        let kept = new.filter { !$0.events.isEmpty }
        guard let store, !kept.isEmpty else { return }
        try? store.add(kept)
        reload()
    }

    func reload() {
        records = store?.all() ?? []
        seenThrough = store?.seenThrough
    }

    func isNew(_ record: DiagnosticRecord) -> Bool { seenThrough.map { record.received > $0 } ?? true }

    var unseen: [DiagnosticRecord] { records.filter(isNew) }

    func markSeen() {
        guard let store, let latest = records.map(\.received).max(), latest != seenThrough else { return }
        try? store.markSeen(through: latest)
        seenThrough = latest
    }

    func removeAll() {
        markSeen()
        try? store?.removeAll()
        reload()
    }
}

private final class Collector: NSObject, MXMetricManagerSubscriber, Sendable {
    let received: @Sendable ([DiagnosticRecord]) -> Void

    init(received: @escaping @Sendable ([DiagnosticRecord]) -> Void) { self.received = received }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let now = Date()
        received(
            payloads.compactMap {
                try? DiagnosticRecord(
                    source: .diagnostic, received: now, span: Self.span($0.timeStampBegin, $0.timeStampEnd), json: $0.jsonRepresentation())
            })
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let now = Date()
        received(
            payloads.compactMap {
                try? DiagnosticRecord(
                    source: .metric, received: now, span: Self.span($0.timeStampBegin, $0.timeStampEnd), json: $0.jsonRepresentation())
            })
    }

    // `DateInterval`은 끝이 시작보다 이르면 멈춘다. MetricKit이 그런 값을 보내지 않는다는 약속은 없다.
    static func span(_ begin: Date, _ end: Date) -> DateInterval { DateInterval(start: min(begin, end), end: max(begin, end)) }
}

#if DEBUG
extension DiagnosticLog {
    // 렌더와 창 스냅숏이 이 Mac의 보고 대신 그리는 보고다. `FOLIO_DIAGNOSTICS_UNSEEN`이 있으면 오늘 화면의 알림도 뜬다.
    static func sample(at now: Date) -> DiagnosticLog {
        let store = DiagnosticStore(url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        let hour: TimeInterval = 3600
        func at(_ hours: Double) -> DateInterval { DateInterval(start: now.addingTimeInterval(-hours * hour), duration: 0) }
        let meta: JSONValue = ["appVersion": "0.4.0", "osVersion": "macOS 26.1 (25B78)"]
        func diagnostic(_ key: String, _ fields: JSONValue) -> JSONValue {
            var merged = meta
            if case .object(let extra) = fields { for (k, v) in extra { merged[k] = v } }
            return [key: [["callStackTree": ["callStackPerThread": true, "callStacks": []], "diagnosticMetaData": merged]]]
        }
        let records = [
            DiagnosticRecord(
                source: .diagnostic, received: now, span: at(2),
                payload: diagnostic("crashDiagnostics", ["exceptionType": 1, "signal": 11])),
            DiagnosticRecord(
                source: .diagnostic, received: now, span: at(5), payload: diagnostic("hangDiagnostics", ["hangDuration": "4.6 sec"])),
            DiagnosticRecord(
                source: .metric, received: now.addingTimeInterval(-30 * hour), span: at(30),
                payload: [
                    "metaData": ["appVersion": "0.3.2"], "memoryMetrics": ["peakMemoryUsage": "2,812,000 kB"],
                    "applicationExitMetrics": ["foregroundExitData": ["cumulativeMemoryResourceLimitExitCount": 2]],
                ]),
            DiagnosticRecord(
                source: .diagnostic, received: now.addingTimeInterval(-50 * hour), span: at(50),
                payload: diagnostic("cpuExceptionDiagnostics", ["appVersion": "0.3.2", "totalCPUTime": "92 sec"])),
        ]
        try? store.add(records)
        let seen = ProcessInfo.processInfo.environment["FOLIO_DIAGNOSTICS_UNSEEN"] == nil ? now : now.addingTimeInterval(-hour)
        try? store.markSeen(through: seen)
        return DiagnosticLog(store: store)
    }
}
#endif
