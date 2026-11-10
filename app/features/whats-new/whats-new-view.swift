import FolioDomain
import SwiftUI

/// 새 기능 (#415): the page an update's sheet, 도움말 › 새 기능 and 설정 › 앱 정보 open.
struct WhatsNewView: View {
    @State private var model: WhatsNewModel

    init(workspace: Workspace) { _model = State(initialValue: WhatsNewModel(workspace: workspace)) }

    var body: some View {
        // Each part a block of the page, `section` apart: the tools, then every version.
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .whatsNewTitle), subtitle: model.subtitle)
            switch model.state {
            case .loading:
                EmptyCard(symbol: "arrow.down.circle", title: String(localized: .whatsNewLoading))
            case .unavailable:
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    EmptyCard(symbol: "wifi.slash", title: String(localized: .whatsNewUnavailable), detail: String(localized: .whatsNewUnavailableDetail))
                    Button(.whatsNewRetry) { Task { await model.retry() } }
                }
            case .empty:
                EmptyCard(symbol: "doc.text", title: String(localized: .whatsNewEmpty))
            case .noMatch, .releases:
                tools
                if case .releases(let releases) = model.state {
                    ForEach(releases, id: \.version) { release in
                        ReleaseSection(model: model, release: release)
                    }
                } else {
                    EmptyLine(model.noMatch)
                }
            }
        }
        .task { await model.load() }
    }

    var tools: some View {
        Group {
            if model.narrow {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SearchField(prompt: String(localized: .whatsNewSearch), text: $model.query)
                    kinds
                }
            } else {
                HStack(spacing: Theme.Space.m) {
                    SearchField(prompt: String(localized: .whatsNewSearch), text: $model.query).frame(maxWidth: 280)
                    kinds
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { model.width = $0 }
    }

    var kinds: some View {
        Segmented(selection: $model.kind, options: model.kindOptions, inks: model.kindOptions.map { $0.0?.tone.foreground })
    }
}

/// One version: its heading, which opens and closes it, then its items in groups by kind.
private struct ReleaseSection: View {
    let model: WhatsNewModel
    let release: PatchNotes.Release

    static let chevron: CGFloat = 12

    var body: some View {
        let open = model.isOpen(release)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button { withAnimation(.snappy) { model.toggle(release) } } label: {
                Group {
                    if model.narrow {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            title(open: open)
                            if model.showsCounts(release) {
                                // Under the version number, past the chevron.
                                KindCounts(counts: model.counts(release)).padding(.leading, Self.chevron + Theme.Space.s)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: Theme.Space.s) {
                            title(open: open)
                            Spacer(minLength: Theme.Space.s)
                            if model.showsCounts(release) { KindCounts(counts: model.counts(release)) }
                        }
                    }
                }
                .frame(minHeight: Theme.Size.touchTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            if open {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    ForEach(PatchNotes.grouped(release.items), id: \.kind) { group in
                        PatchNoteGroup(group: group)
                    }
                }
            }
        }
    }

    func title(open: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "chevron.right")
                .font(Theme.Glyph.small)
                .foregroundStyle(Theme.Palette.textTertiary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: Self.chevron)
            Text(release.version.description).font(Theme.Typeface.figureMedium).monospacedDigit()
            if model.isCurrent(release) { Chip(String(localized: .whatsNewCurrent), tone: .accent) }
            if let date = model.date(release) { Text(date).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1) }
        }
        .fixedSize()
    }
}

/// The items of one kind under its chip (`feat`, `fix`, `change`), on the page and in the sheet alike.
struct PatchNoteGroup: View {
    let group: PatchNotes.Group
    /// Before a row's link opens: the sheet closes itself first.
    var opening: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Chip(group.kind.label, tone: group.kind.tone)
            Card {
                ForEach(Array(group.items.enumerated()), id: \.offset) { i, item in
                    CardRow(last: i == group.items.count - 1) { PatchNoteRow(item: item, opening: opening) }
                }
            }
        }
    }
}

/// `feat 3  fix 2`: each kind's chip and how many.
struct KindCounts: View {
    let counts: [PatchNotes.Count]

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(counts, id: \.kind) { count in
                HStack(spacing: Theme.Space.xxs) {
                    Chip(count.kind.label, tone: count.kind.tone)
                    Text(String(localized: .whatsNewCount(count.count))).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .fixedSize()
            }
        }
    }
}

/// One item: its sentence and, when it names a place, 열기.
struct PatchNoteRow: View {
    let item: PatchNotes.Item
    var opening: () -> Void = {}
    @Environment(\.openLink) private var openLink

    var body: some View {
        Text(item.text).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        if let link = item.link {
            Button(.commonOpen) {
                opening()
                openLink(link)
            }
            .buttonStyle(.ghost)
            .contentShape(TouchTarget())
        }
    }
}
