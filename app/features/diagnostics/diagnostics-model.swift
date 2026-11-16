import FolioCore
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class DiagnosticsModel {
    let workspace: Workspace
    var exporting: DiagnosticFile?
    var confirmingDelete = false

    static let rowLimit = 20

    init(workspace: Workspace) { self.workspace = workspace }

    var log: DiagnosticLog { workspace.diagnostics }

    struct Row: Identifiable, Equatable {
        let id: String
        let kind: DiagnosticEvent.Kind
        let title: String
        let detail: String?
        let when: String
        let isNew: Bool
    }

    var allRows: [Row] {
        log.records.flatMap { record in
            record.events.enumerated().map { i, event in row(event, id: "\(record.id)-\(i)", isNew: log.isNew(record)) }
        }
    }

    var rows: [Row] { Array(allRows.prefix(Self.rowLimit)) }

    var isEmpty: Bool { log.records.isEmpty }

    var note: String? { allRows.count > Self.rowLimit ? String(localized: .diagnosticsRecent(Self.rowLimit)) : nil }

    func row(_ event: DiagnosticEvent, id: String, isNew: Bool) -> Row {
        let title = event.count > 1 ? String(localized: .diagnosticsTimes(event.kind.label, event.count)) : event.kind.label
        let detail = [event.detail, event.appVersion.map { String(localized: .diagnosticsVersion($0)) }].compactMap(\.self)
        return Row(
            id: id, kind: event.kind, title: title, detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
            when: when(event.date), isNew: isNew)
    }

    func when(_ date: Date) -> String {
        let calendar = workspace.calendar
        let day = calendar.dateComponents([.month, .day], from: date)
        let monthDay = String(localized: .commonMonthDay(day.month ?? 0, day.day ?? 0))
        return String(localized: .diagnosticsWhen(monthDay, ClockText.minute(calendar.minuteOfDay(date))))
    }

    // 알림에는 아직 보지 않은 보고만 센다.
    var newCount: Int { log.unseen.map { $0.events.reduce(0) { $0 + $1.count } }.reduce(0, +) }

    var noticeTitle: String { String(localized: .diagnosticsNoticeTitle(newCount)) }

    var noticeDetail: String {
        let kinds = DiagnosticEvent.Kind.allCases.filter { kind in log.unseen.contains { $0.events.contains { $0.kind == kind } } }
        return kinds.map(\.label).joined(separator: ", ")
    }

    func export() {
        exporting = DiagnosticFile(
            export: DiagnosticExport(exported: workspace.now, appVersion: ReleaseNotes.appVersion.description, records: log.records))
    }

    var exportName: String { DiagnosticExport.fileName(at: workspace.now, calendar: workspace.calendar) }

    func exported() {
        exporting = nil
        log.markSeen()
    }

    func markSeen() { log.markSeen() }

    func removeAll() { log.removeAll() }
}

extension DiagnosticEvent.Kind {
    var label: String {
        switch self {
        case .crash: String(localized: .diagnosticsKindCrash)
        case .hang: String(localized: .diagnosticsKindHang)
        case .cpu: String(localized: .diagnosticsKindCpu)
        case .diskWrite: String(localized: .diagnosticsKindDiskWrite)
        case .memory: String(localized: .diagnosticsKindMemory)
        }
    }

    var symbol: String {
        switch self {
        case .crash: "xmark.octagon"
        case .hang: "hourglass"
        case .cpu: "cpu"
        case .diskWrite: "internaldrive"
        case .memory: "memorychip"
        }
    }

    var tone: Tone {
        switch self {
        case .crash, .memory: .danger
        case .hang, .cpu, .diskWrite: .warning
        }
    }
}
