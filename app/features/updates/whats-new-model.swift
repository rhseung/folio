import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class WhatsNewModel {
    let workspace: Workspace
    var query = ""
    var kind: PatchNotes.Kind?
    private var toggled: Set<String> = []
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
        case series([PatchNotes.Series])
    }

    var state: State {
        guard let history = notes.history else { return notes.feed == .failed ? .unavailable : .loading }
        guard !history.isEmpty else { return .empty }
        let shown = PatchNotes.filter(history, kind: kind, query: query)
        return shown.isEmpty ? .noMatch : .series(PatchNotes.series(shown))
    }

    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    // 지금 버전이 든 minor만 펼친다. patch는 PR마다 나와서 모두 펼치면 페이지가 끝없이 길어진다.
    func isOpen(_ series: PatchNotes.Series) -> Bool {
        searching || series.contains(notes.current) != toggled.contains(series.name)
    }

    func toggle(_ series: PatchNotes.Series) {
        guard !searching else { return }
        if toggled.contains(series.name) { toggled.remove(series.name) } else { toggled.insert(series.name) }
    }

    func isCurrent(_ series: PatchNotes.Series) -> Bool { series.contains(notes.current) }

    // 릴리스가 하나뿐인 묶음은 묶음 제목이 그 릴리스를 말하므로 릴리스마다의 제목을 두지 않는다.
    func showsReleases(_ series: PatchNotes.Series) -> Bool { series.releases.count > 1 }

    // 그 minor가 끝낸 기능 묶음을 제목에 붙인다("0.6 · LMS 연동").
    func title(_ series: PatchNotes.Series) -> String {
        let version = showsReleases(series) ? series.name : series.latest.version.description
        guard !series.bundles.isEmpty else { return version }
        return String(localized: .whatsNewSeriesBundle(version, series.bundles.formatted(.list(type: .and))))
    }

    func days(_ series: PatchNotes.Series) -> String? {
        let first = date(series.first), last = date(series.latest)
        guard let first, let last, first != last else { return last ?? first }
        return String(localized: .whatsNewDays(first, last))
    }

    func load() async { await notes.load() }

    func retry() async { await notes.reload() }

    var subtitle: String { String(localized: .whatsNewSubtitle(notes.current.description)) }

    var kindOptions: [(PatchNotes.Kind?, String)] {
        [(nil, String(localized: .whatsNewKindAll))] + PatchNotes.Kind.allCases.map { ($0, $0.label) }
    }

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
