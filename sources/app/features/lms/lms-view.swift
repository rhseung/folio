import FolioDomain
import SwiftUI

struct LMSView: View {
    @State private var model: LMSModel
    @Environment(\.place) private var place

    init(workspace: Workspace) { _model = State(initialValue: LMSModel(workspace: workspace)) }

    var body: some View {
        let board = model.board
        let shown = model.shown(in: board)
        ColumnSplit(kind: .lms) {
            LMSColumn(model: model, board: board)
        } content: {
            Page(maxWidth: 760) {
                PageHeader(title: model.title(of: shown), subtitle: model.subtitle(of: shown))
                content(shown)
            }
            .id(model.page)
        }
        .onChange(of: place, initial: true) { _, entry in if let entry { model.follow(entry.link) } }
    }

    @ViewBuilder func content(_ shown: LMSModel.Shown) -> some View {
        switch shown {
        case .all(let groups):
            if !model.isConnected { ConnectNotice() }
            if groups.isEmpty {
                EmptyCard(
                    systemImage: "tray", tone: model.isConnected ? .success : .plain, title: String(localized: .lmsEmpty),
                    detail: model.emptyDetail)
            }
            ForEach(groups) { g in
                Block(g.group.name, note: model.count(g.proposals)) {
                    Card {
                        ForEach(g.proposals) { p in
                            ProposalRow(model: model, proposal: p, source: true, last: p.id == g.proposals.last?.id)
                        }
                    }
                }
            }
        case .room(let room):
            RoomBlock(model: model, room: room).crumb(room.classroom.title, level: 1, symbol: LMSColumn.roomSymbol)
        case .gone:
            EmptyCard(systemImage: "tray", tone: .success, title: String(localized: .lmsEmpty))
        }
    }
}

// 그 자리에서 준 `closeColumn`을 페이지 위에 연 열이 읽도록 따로 뷰로 둔다.
private struct LMSColumn: View {
    let model: LMSModel
    let board: ProposalBoard
    @Environment(\.closeColumn) private var closeColumn
    @Environment(\.openLink) private var openLink

    static let roomSymbol = "building.columns"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(.rootNavLms).font(Theme.Typeface.columnTitle).padding(.horizontal, Theme.Inset.listRow.leading)
                row(String(localized: .lmsAll), symbol: "tray", page: nil, count: board.count)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Caption(String(localized: .lmsRooms)).padding(.horizontal, Theme.Inset.listRow.leading).padding(.bottom, Theme.Space.xs)
                    if !model.isConnected { ConnectRow() }
                    ForEach(board.rooms) { r in
                        row(r.classroom.title, symbol: Self.roomSymbol, page: .classroom(r.id), count: r.proposals.count)
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
            .clearOfColumnButtons(inset: Theme.Space.l)
        }
        .overflowFade(.vertical)
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .columnBackground()
    }

    func row(_ title: String, symbol: String, page: AppLink.LMSPage?, count: Int) -> some View {
        Button {
            openLink(.lms(page))
            closeColumn()
        } label: {
            ColumnRow(title: title, symbol: symbol, chosen: model.page == page) {
                if count > 0 {
                    Text("\(count)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .buttonStyle(.pointing(.plain))
    }
}

// 흐리게 막은 행은 이유를 알 수 없고 터치로 찾기 어려워서, 연결하지 않았으면 그 자리에 연결하는 길을 둔다(#132).
private struct ConnectRow: View {
    @Environment(\.openLink) private var openLink

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(.lmsNotConnected).foregroundStyle(Theme.Palette.textSecondary)
            Button(.lmsConnectInSettings) { openLink(.settings(.lms)) }.buttonStyle(.secondary)
        }
        .padding(.horizontal, Theme.Inset.listRow.leading)
        .padding(.vertical, Theme.Space.xs)
    }
}

private struct ConnectNotice: View {
    @Environment(\.openLink) private var openLink

    var body: some View {
        NoticeCard(title: String(localized: .lmsNotConnected), systemImage: "link", informs: true) {
            Button(.lmsConnectInSettings) { openLink(.settings(.lms)) }.buttonStyle(.prominent)
        } rows: {
            EmptyView()
        }
    }
}

private struct RoomBlock: View {
    let model: LMSModel
    let room: ProposalBoard.Room
    @Environment(\.openURL) private var openURL

    var body: some View {
        Block(
            title: String(localized: .lmsItems), note: model.count(room.proposals),
            trailing: {
                Button {
                    openURL(room.classroom.url)
                } label: {
                    Label(.lmsOpen, systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
                if !room.proposals.isEmpty { RoomActions(model: model, proposals: room.proposals) }
            },
            content: {
                Card {
                    if room.proposals.isEmpty, room.hidden.isEmpty {
                        CardRow(last: true) { Text(.lmsEmpty).foregroundStyle(Theme.Palette.textTertiary) }
                    }
                    ForEach(room.proposals) { p in
                        ProposalRow(model: model, proposal: p, source: false, last: room.hidden.isEmpty && p.id == room.proposals.last?.id)
                    }
                    if !room.hidden.isEmpty {
                        DisclosureRow(
                            label: String(localized: .lmsHidden(room.hidden.count)),
                            isExpanded: Binding(get: { model.showingHidden }, set: { model.showingHidden = $0 }), last: true
                        ) {
                            ForEach(room.hidden) { h in
                                HiddenRow(model: model, hidden: h, last: h.id == room.hidden.last?.id)
                            }
                        }
                    }
                }
            })
    }
}

private struct RoomActions: View {
    let model: LMSModel
    let proposals: [Proposal]

    var body: some View {
        let addable = model.addable(proposals)
        if addable.isEmpty {
            Button(.lmsDismissAll) { model.dismiss(proposals) }.buttonStyle(.secondary)
        } else {
            TargetCourseMenu(model: model, label: String(localized: .lmsAddAll)) { course in
                Task { await model.add(addable, into: course) }
            } more: {
                Divider()
                Button(.lmsDismissAll, role: .destructive) { model.dismiss(proposals) }
            }
            .disabled(model.isAdding(addable))
        }
    }
}

private struct ProposalRow: View {
    let model: LMSModel
    let proposal: Proposal
    let source: Bool
    let last: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardRow(last: last) {
            LineIcon(symbol: proposal.kind.symbol).foregroundStyle(Theme.Palette.textSecondary)
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(model.title(proposal)).lineLimit(2)
                        if let flag = proposal.flag { Badge(flag.label, tone: .warning) }
                        if let due = model.due(proposal) { DueChip(text: due.text, urgency: due.urgency) }
                    }
                    if let detail = model.detail(proposal, source: source) {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } control: {
                HStack(spacing: Theme.Space.s) {
                    if model.showsOpen(proposal), let url = proposal.url {
                        Button {
                            openURL(url)
                        } label: {
                            Label(.lmsOpen, systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
                    }
                    if proposal.canDismiss { Button(.lmsDismiss) { model.dismiss([proposal]) }.buttonStyle(.secondary) }
                    approve
                }
                .fixedSize()
            }
        }
        .contextMenu {
            if let url = proposal.url { Button(.lmsOpen) { openURL(url) } }
            if proposal.canDismiss { Button(.lmsDismiss) { model.dismiss([proposal]) } }
        }
    }

    @ViewBuilder var approve: some View {
        if proposal.kind.picksCourse, proposal.canApprove {
            TargetCourseMenu(model: model, label: String(localized: .commonAdd), strong: true) { course in
                Task { await model.add([proposal], into: course) }
            }
            .disabled(model.isAdding([proposal]))
        }
    }
}

private struct HiddenRow: View {
    let model: LMSModel
    let hidden: LMSInbox.Handled
    let last: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardRow(last: last) {
            LineIcon(symbol: hidden.proposal.proposal().kind.symbol).foregroundStyle(Theme.Palette.textTertiary)
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(hidden.proposal.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    Text(model.detail(hidden)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        .truncationMode(.middle)
                }
            } control: {
                HStack(spacing: Theme.Space.s) {
                    Button {
                        openURL(hidden.proposal.url)
                    } label: {
                        Label(.lmsOpen, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
                    if hidden.proposable { Button(.lmsRestore) { model.proposeAgain(hidden) }.buttonStyle(.secondary) }
                }
                .fixedSize()
            }
        }
        .contextMenu {
            Button(.lmsOpen) { openURL(hidden.proposal.url) }
            if hidden.proposable { Button(.lmsRestore) { model.proposeAgain(hidden) } }
        }
    }
}

private struct DueChip: View {
    let text: String
    let urgency: DueUrgency

    var body: some View {
        switch urgency {
        case .urgent: Badge(text, tone: .danger, solid: true).monospacedDigit()
        case .soon: Badge(text, tone: .warning).monospacedDigit()
        case .later: Badge(text).monospacedDigit()
        }
    }
}
