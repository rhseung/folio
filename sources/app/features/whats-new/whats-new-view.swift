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

struct PatchNoteList: View {
    let items: [PatchNotes.Item]
    var maxHeight: CGFloat?
    var opening: () -> Void = {}
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        Card {
            if let maxHeight {
                ScrollView {
                    VStack(spacing: 0) { rows }
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            rowsHeight = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .overflowFade(.vertical)
                // ScrollView는 받은 높이를 모두 차지하므로, 짧은 목록이 짧게 남도록 행 높이에 맞춘다.
                .frame(height: min(rowsHeight, maxHeight))
            } else {
                rows
            }
        }
    }

    var rows: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
            CardRow(last: i == items.count - 1) { PatchNoteRow(item: item, opening: opening) }
        }
    }
}

struct PatchNoteRow: View {
    let item: PatchNotes.Item
    var opening: () -> Void = {}
    @Environment(\.openLink) private var openLink

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(PatchNotes.Kind.allCases, id: \.self) { Chip($0.label, tone: $0.tone).hidden() }
            Chip(item.kind.label, tone: item.kind.tone)
        }
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
