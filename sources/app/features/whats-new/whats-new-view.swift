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
                EmptyCard(symbol: "arrow.down.circle", title: String(localized: .whatsNewLoading))
            case .unavailable:
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    EmptyCard(
                        symbol: "wifi.slash", title: String(localized: .whatsNewUnavailable),
                        detail: String(localized: .whatsNewUnavailableDetail))
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

private struct ReleaseSection: View {
    let model: WhatsNewModel
    let release: PatchNotes.Release

    var body: some View {
        let open = model.isOpen(release)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button {
                withAnimation(.snappy) { model.toggle(release) }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "chevron.right")
                        .font(Theme.Glyph.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(release.version.description).font(Theme.Typeface.figureMedium).monospacedDigit()
                    if model.isCurrent(release) { Chip(String(localized: .whatsNewCurrent), tone: .accent) }
                    if let date = model.date(release) { Text(date).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            if open { PatchNoteList(items: model.items(release)) }
        }
    }
}
