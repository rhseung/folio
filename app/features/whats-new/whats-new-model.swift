import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class WhatsNewModel {
    let workspace: Workspace
    var query = ""
    var kind: PatchNotes.Kind?
    private var toggled: Set<PatchNotes.Version> = []
    var width: CGFloat = 0

    static let wideFrom: CGFloat = 560

    var narrow: Bool { width < Self.wideFrom }

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    var notes: ReleaseNotes { workspace.releaseNotes }

    enum State: Equatable {
        case loading
        case unavailable
        case empty
        case noMatch
        case releases([PatchNotes.Release])
    }

    var state: State {
        guard let history = notes.history else { return notes.feed == .failed ? .unavailable : .loading }
        guard !history.isEmpty else { return .empty }
        let shown = PatchNotes.filter(history, kind: kind, query: query)
        return shown.isEmpty ? .noMatch : .releases(shown)
    }

    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func isOpen(_ release: PatchNotes.Release) -> Bool {
        searching || (release.version == notes.current) != toggled.contains(release.version)
    }

    func toggle(_ release: PatchNotes.Release) {
        guard !searching else { return }
        if toggled.contains(release.version) { toggled.remove(release.version) } else { toggled.insert(release.version) }
    }

    func load() async { await notes.load() }

    func retry() async { await notes.reload() }

    var subtitle: String { String(localized: .whatsNewSubtitle(notes.current.description)) }

    var kindOptions: [(PatchNotes.Kind?, String)] {
        [(nil, String(localized: .whatsNewKindAll))] + PatchNotes.Kind.allCases.map { ($0, $0.label) }
    }

    func isCurrent(_ release: PatchNotes.Release) -> Bool { release.version == notes.current }

    func date(_ release: PatchNotes.Release) -> String? {
        release.date.map { Self.day($0, calendar: workspace.calendar) }
    }

    func items(_ release: PatchNotes.Release) -> [PatchNotes.Item] { PatchNotes.ordered(release.items) }

    var noMatch: String {
        let words = query.trimmingCharacters(in: .whitespaces)
        let base = words.isEmpty ? String(localized: .whatsNewNoItems) : String(localized: .whatsNewNoMatch(words))
        return kind.map { String(localized: .whatsNewNoMatchKind(base, $0.label)) } ?? base
    }

    nonisolated static func day(_ date: Date, calendar: Calendar) -> String {
        let d = calendar.dateComponents([.month, .day], from: date)
        return String(localized: .commonMonthDay(d.month ?? 0, d.day ?? 0))
    }
}

extension PatchNotes.Kind {
    var label: String { rawValue }

    var tone: Tone {
        switch self {
        case .feat: .info
        case .fix: .success
        case .change: .warning
        }
    }
}

extension PatchNotes.Summary {
    func subtitle(calendar: Calendar) -> String {
        let version = latest.version.description
        if releases.count > 1 { return String(localized: .whatsNewSheetSeveral(version, since.description, releases.count)) }
        guard let date = latest.date else { return String(localized: .whatsNewSubtitle(version)) }
        return String(localized: .whatsNewSheetOne(version, WhatsNewModel.day(date, calendar: calendar)))
    }
}
