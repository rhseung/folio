import FolioCore
import Foundation

// MetricKit 보고 하나다. 원문 JSON은 경로를 지운 채(`DiagnosticRedaction`) 그대로 두어, 내보낸 파일로 호출 스택까지 볼 수 있게 한다.
public struct DiagnosticRecord: Codable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case diagnostic
        case metric
    }

    public var schemaVersion = 1
    public var id: UUID
    public var source: Source
    public var received: Date
    public var span: DateInterval
    public var payload: JSONValue

    public init(source: Source, received: Date, span: DateInterval, payload: JSONValue, id: UUID = UUID()) {
        self.id = id
        self.source = source
        self.received = received
        self.span = span
        self.payload = DiagnosticRedaction.redact(payload)
    }

    public init(source: Source, received: Date, span: DateInterval, json: Data, id: UUID = UUID()) throws {
        self.init(source: source, received: received, span: span, payload: try JSONDecoder().decode(JSONValue.self, from: json), id: id)
    }

    public var events: [DiagnosticEvent] {
        switch source {
        case .diagnostic: diagnosticEvents
        case .metric: metricEvents
        }
    }

    // MetricKit은 하루 치를 묶어 보낼 수 있다. 그래도 화면에서는 보고를 받은 구간의 끝이 일어난 때에 가장 가깝다.
    var date: Date { span.end }

    var diagnosticEvents: [DiagnosticEvent] {
        let groups: [(key: String, kind: DiagnosticEvent.Kind)] = [  // strings: data, MetricKit JSON keys
            ("crashDiagnostics", .crash), ("hangDiagnostics", .hang), ("cpuExceptionDiagnostics", .cpu),
            ("diskWriteExceptionDiagnostics", .diskWrite),
        ]
        return groups.flatMap { group -> [DiagnosticEvent] in
            guard case .array(let items) = payload[group.key] else { return [] }
            return items.map { item in
                let meta = item["diagnosticMetaData"]
                return DiagnosticEvent(
                    kind: group.kind, date: date, appVersion: meta?["appVersion"]?.text,
                    detail: Self.detail(group.kind, meta: meta))
            }
        }
    }

    // 하루 치 지표에서는 메모리 한도를 넘어 꺼진 횟수만 사건으로 본다. 최대 메모리는 그날 하루에 쓴 양이라 함께 적는다.
    var metricEvents: [DiagnosticEvent] {
        let exits = payload["applicationExitMetrics"]
        let count = ["foregroundExitData", "backgroundExitData"]  // strings: data, MetricKit JSON keys
            .compactMap { exits?[$0]?["cumulativeMemoryResourceLimitExitCount"]?.int }.reduce(0, +)
        guard count > 0 else { return [] }
        let version = payload["metaData"]?["appVersion"]?.text ?? payload["appVersion"]?.text
        return [
            DiagnosticEvent(
                kind: .memory, date: date, appVersion: version, detail: payload["memoryMetrics"]?["peakMemoryUsage"]?.text, count: count)
        ]
    }

    static func detail(_ kind: DiagnosticEvent.Kind, meta: JSONValue?) -> String? {
        switch kind {
        case .crash:
            if let name = meta?["objectiveCexceptionReason"]?["exceptionName"]?.text { return name }
            let parts = [
                meta?["exceptionType"]?.int.map { exceptionNames[$0] ?? "EXC \($0)" },  // strings: data, Mach exception name
                meta?["signal"]?.int.map { signalNames[$0] ?? "SIG \($0)" },  // strings: data, signal name
            ]
            .compactMap(\.self)
            return parts.isEmpty ? meta?["terminationReason"]?.text : parts.joined(separator: " · ")
        case .hang: return meta?["hangDuration"]?.text
        case .cpu: return meta?["totalCPUTime"]?.text
        case .diskWrite: return meta?["writesCaused"]?.text
        case .memory: return nil
        }
    }

    // <mach/exception_types.h>와 <sys/signal.h>의 번호다. 크래시 보고서가 보여 주는 이름과 같게 적는다.
    static let exceptionNames: [Int: String] = [  // strings: data, Mach exception names
        1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
        6: "EXC_BREAKPOINT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD",
    ]
    static let signalNames: [Int: String] = [  // strings: data, signal names
        4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE",
    ]
}

extension JSONValue {
    fileprivate var text: String? {
        switch self {
        case .string(let s) where !s.isEmpty: s
        // 1e20 같은 값은 Int로 바꾸면 멈추므로 정확히 바뀌는 값만 정수로 적는다.
        case .number(let n): Int(exactly: n).map(String.init) ?? String(n)
        default: nil
        }
    }

    fileprivate var int: Int? {
        switch self {
        case .number(let n): Int(exactly: n)
        case .string(let s): Int(s)
        default: nil
        }
    }
}
