import FolioDomain
import SwiftUI

struct WhatsNewView: View {
    @State private var model: WhatsNewModel

    init(workspace: Workspace) { _model = State(initialValue: WhatsNewModel(workspace: workspace)) }

    var body: some View {
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .whatsNewTitle), subtitle: model.subtitle)
            switch model.state {
            case .loading:
                EmptyCard(systemImage: "arrow.down.circle", title: String(localized: .whatsNewLoading))
            case .unavailable:
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    EmptyCard(
                        systemImage: "wifi.slash", title: String(localized: .whatsNewUnavailable),
                        detail: String(localized: .whatsNewUnavailableDetail))
                    Button(.whatsNewRetry) { Task { await model.retry() } }
                }
            case .empty:
                EmptyCard(systemImage: "doc.text", title: String(localized: .whatsNewEmpty))
            case .noMatch, .series:
                tools
                if case .series(let all) = model.state {
                    ForEach(all, id: \.name) { series in
                        SeriesSection(model: model, series: series)
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
                    SearchField(prompt: String(localized: .whatsNewSearch), text: $model.query).frame(maxWidth: Theme.Size.pageSearch)
                    kinds
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { model.width = $0 }
    }

    var kinds: some View {
        SegmentedControl(selection: $model.kind, options: model.kindOptions, tints: model.kindOptions.map { $0.0?.tone.foreground })
    }
}

private struct SeriesSection: View {
    let model: WhatsNewModel
    let series: PatchNotes.Series

    var body: some View {
        let open = model.isOpen(series)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button {
                withAnimation(.snappy) { model.toggle(series) }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "chevron.right")
                        .font(Theme.Glyph.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(model.title(series))
                        .font(Theme.Typeface.figureMedium).monospacedDigit()
                    if model.isCurrent(series) { Badge(String(localized: .whatsNewCurrent), tone: .accent) }
                    if let days = model.days(series) { Text(days).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            if open {
                if model.showsReleases(series) {
                    ForEach(series.releases, id: \.version) { release in
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            HStack(spacing: Theme.Space.s) {
                                Text(release.version.description).font(Theme.Typeface.bodyStrong).monospacedDigit()
                                if let date = model.date(release) {
                                    Text(date).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                                }
                            }
                            PatchNoteList(items: model.items(release))
                        }
                    }
                } else {
                    PatchNoteList(items: model.items(series.latest))
                }
            }
        }
    }
}
