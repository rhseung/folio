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

/// One version: its heading, which opens and closes it, then its items.
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

/// Items in one card, each after its kind's chip, on the page and in the sheet alike.
struct PatchNoteList: View {
    let items: [PatchNotes.Item]
    /// Past this height the rows scroll inside the card, the edge with more past it faded; nil grows with the rows.
    var maxHeight: CGFloat?
    /// Before a row's link opens: the sheet closes itself first.
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
                // A ScrollView takes all the height it is offered; sized to its rows, a short list stays short.
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

/// One item: its kind, its sentence and, when it names a place, 열기.
struct PatchNoteRow: View {
    let item: PatchNotes.Item
    var opening: () -> Void = {}
    @Environment(\.openLink) private var openLink

    var body: some View {
        // As wide as the widest kind's chip, so every row's sentence starts at one edge.
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
