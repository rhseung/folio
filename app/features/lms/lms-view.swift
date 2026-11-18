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
                PageHeader(title: model.title(of: shown), subtitle: model.subtitle(of: shown)) {
                    if case .room(let room) = shown {
                        RoomCourseMenu(model: model, room: room)
                        OpenButton(url: room.classroom.url)
                    }
                    if let chip = model.statusChip { Badge(chip.text, tone: chip.tone) }
                }
                if model.needsLogin { LoginEndedNotice() }
                content(shown)
            }
            .id(model.page)
        }
        .onChange(of: place, initial: true) { _, entry in if let entry { model.follow(entry.link) } }
    }

    @ViewBuilder func content(_ shown: LMSModel.Shown) -> some View {
        switch shown {
        case .all(let sections):
            if !model.isConnected { ConnectNotice() }
            if sections.isEmpty {
                EmptyCard(
                    systemImage: "tray", tone: model.isConnected ? .success : .plain, title: String(localized: .lmsEmpty),
                    detail: model.emptyDetail)
            }
            ForEach(sections) { SectionBlock(model: model, section: $0, source: true) }
        case .room(let room):
            RoomPage(model: model, room: room).crumb(room.classroom.title, level: 1, symbol: LMSColumn.roomSymbol)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let note = model.syncNote {
                Caption(note).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Inset.panel + Theme.Inset.listRow.leading).padding(.vertical, Theme.Space.l)
            }
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

// 흐리게 막은 행은 이유를 알 수 없고 터치로 찾기 어려워서, 연결하지 않았으면 그 자리에 연결하는 길을 둔다.
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

// LMS가 로그인을 받지 않으면 다시 시도하지 않고 마지막으로 읽은 내용을 보이며 다시 연결하게 한다.
private struct LoginEndedNotice: View {
    @Environment(\.openLink) private var openLink

    var body: some View {
        NoticeCard(title: String(localized: .lmsLoginEnded), detail: String(localized: .lmsNeedsLogin), systemImage: "link", tone: .warning)
        {
            Button(.lmsReconnect) { openLink(.settings(.lms)) }.buttonStyle(.prominent)
        }
    }
}

private struct ConnectNotice: View {
    @Environment(\.openLink) private var openLink

    var body: some View {
        NoticeCard(title: String(localized: .lmsNotConnected), systemImage: "link", tone: .info) {
            Button(.lmsConnectInSettings) { openLink(.settings(.lms)) }.buttonStyle(.prominent)
        }
    }
}

// 무리마다 블록 하나다. 새로 올라온 것은 기억한 과목에 모두 받고, 새 글은 모두 읽는다. 고칠 것은 하나씩 처리한다.
private struct SectionBlock: View {
    let model: LMSModel
    let section: LMSModel.Section
    let source: Bool
    var room: ProposalBoard.Room?

    var body: some View {
        switch section {
        case .group(let g):
            Block(
                title: g.group.name, note: model.count(g.proposals),
                trailing: { trailing(g) },
                content: {
                    Card {
                        ForEach(g.proposals) { p in
                            ProposalRow(model: model, proposal: p, source: source, last: p.id == g.proposals.last?.id)
                        }
                    }
                })
        case .deadlines(let deadlines):
            Block(String(localized: .lmsDeadlines), note: "\(deadlines.count)") {
                Card {
                    ForEach(deadlines) { d in DeadlineRow(model: model, deadline: d, source: source, last: d.id == deadlines.last?.id) }
                }
            }
        }
    }

    @ViewBuilder func trailing(_ g: ProposalBoard.Group) -> some View {
        switch g.group {
        case .new:
            if let room {
                RoomActions(model: model, room: room, proposals: g.proposals)
            } else if !model.remembered.isEmpty {
                Button(.lmsAddRemembered) { Task { await model.addRemembered() } }.buttonStyle(.secondary)
                    .disabled(model.isAdding(model.remembered))
            }
        case .posts:
            Button(.lmsReadAll) { model.dismiss(g.proposals) }.buttonStyle(.secondary)
        case .differs:
            EmptyView()
        }
    }
}

private struct RoomPage: View {
    let model: LMSModel
    let room: ProposalBoard.Room

    var body: some View {
        let sections = model.sections(of: room)
        if sections.isEmpty, room.hidden.isEmpty {
            EmptyCard(systemImage: "tray", tone: .success, title: String(localized: .lmsEmpty))
        }
        ForEach(sections) { SectionBlock(model: model, section: $0, source: false, room: room) }
        if !room.hidden.isEmpty {
            Card {
                DisclosureRow(
                    label: String(localized: .lmsHidden(room.hidden.count)),
                    isExpanded: Binding(get: { model.showingHidden }, set: { model.showingHidden = $0 }), last: true
                ) {
                    ForEach(room.hidden) { h in HiddenRow(model: model, hidden: h, last: h.id == room.hidden.last?.id) }
                }
            }
        }
    }
}

private struct OpenButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(.lmsOpen, systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
    }
}

// 강의실 머리의 칩이다. 받을 때 고른 과목을 강의실마다 기억하고, 여기서 바꾸거나 과목 없음으로 두거나 지운다.
private struct RoomCourseMenu: View {
    let model: LMSModel
    let room: ProposalBoard.Room

    var body: some View {
        Menu {
            Section(String(localized: .lmsRoomCourse)) {
                ForEach(model.targets, id: \.id) { course in
                    Toggle(
                        course.title,
                        isOn: Binding(get: { room.course == course.id }, set: { _ in model.remember(room.id, course: course.id) }))
                }
            }
            Divider()
            Toggle(
                String(localized: .lmsNoCourse),
                isOn: Binding(get: { room.memory != nil && room.course == nil }, set: { _ in model.rememberNoCourse(room.id) }))
            if room.memory != nil {
                Button(.lmsForgetCourse, role: .destructive) { model.forget(room.id) }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(model.memoryLabel(room))
                Image(systemName: "chevron.down").font(Theme.Glyph.small).accessibilityHidden(true)
            }
        }
        .menuStyle(.button).buttonStyle(.secondary).menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct RoomActions: View {
    let model: LMSModel
    let room: ProposalBoard.Room
    let proposals: [Proposal]

    var body: some View {
        let addable = model.addable(proposals)
        if addable.isEmpty {
            Button(.lmsDismissAll) { model.dismiss(proposals) }.buttonStyle(.secondary)
        } else {
            TargetCourseMenu(model: model, label: String(localized: .lmsAddAll), remembered: model.remembered(room.id), all: true) {
                course in
                Task { await model.add(addable, into: course) }
            } more: {
                Divider()
                Button(.lmsDismissAll, role: .destructive) { model.dismiss(proposals) }
            }
            .disabled(model.isAdding(addable))
        }
    }
}

// 행을 누르면 LMS에서 연다. 단추는 할 일 하나만 두고, 무시는 그 단추의 메뉴와 행의 메뉴에 둔다.
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
                RowText(title: model.title(proposal), detail: model.detail(proposal, source: source))
            } control: {
                HStack(spacing: Theme.Space.m) {
                    if let due = model.due(proposal) { DueText(due: due) }
                    action
                }
                .fixedSize()
            }
        }
        .opens(proposal.url.map { url in { openURL(url) } })
        .accessibilityAction(named: Text(.lmsOpen)) { if let url = proposal.url { openURL(url) } }
        .contextMenu {
            if let url = proposal.url { Button(.lmsOpen) { openURL(url) } }
            if proposal.canDismiss { Button(.lmsDismiss) { model.dismiss([proposal]) } }
        }
    }

    @ViewBuilder var action: some View {
        if proposal.kind.picksCourse, proposal.canApprove {
            TargetCourseMenu(model: model, label: String(localized: .commonAdd), remembered: model.remembered(proposal), strong: true) {
                course in
                Task { await model.add([proposal], into: course) }
            } more: {
                dismiss
            }
            .disabled(model.isAdding([proposal]))
        } else if let label = model.fixLabel(proposal), proposal.canApprove {
            HStack(spacing: Theme.Space.xs) {
                Button(label) { Task { await model.fix(proposal) } }.buttonStyle(.secondary(strong: true))
                if proposal.canDismiss {
                    Menu {
                        dismiss
                    } label: {
                        Image(systemName: "chevron.down").font(Theme.Glyph.small).accessibilityLabel(String(localized: .lmsMore))
                    }
                    .menuStyle(.button).buttonStyle(.secondary(iconOnly: true)).menuIndicator(.hidden).fixedSize()
                    .help(String(localized: .lmsMore))
                }
            }
            .disabled(model.isAdding([proposal]))
        }
    }

    @ViewBuilder var dismiss: some View {
        if proposal.canDismiss {
            Divider()
            Button(.lmsDismiss, role: .destructive) { model.dismiss([proposal]) }
        }
    }
}

private struct RowText: View {
    let title: String
    let detail: String?
    var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).foregroundStyle(dim ? Theme.Palette.textSecondary : Theme.Palette.text).lineLimit(2)
            if let detail {
                Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    .truncationMode(.middle)
            }
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
                RowText(title: hidden.proposal.title, detail: model.detail(hidden), dim: true)
            } control: {
                if hidden.proposable { Button(.lmsRestore) { model.proposeAgain(hidden) }.buttonStyle(.secondary).fixedSize() }
            }
        }
        .opens { openURL(hidden.proposal.url) }
        .accessibilityAction(named: Text(.lmsOpen)) { openURL(hidden.proposal.url) }
        .contextMenu {
            Button(.lmsOpen) { openURL(hidden.proposal.url) }
            if hidden.proposable { Button(.lmsRestore) { model.proposeAgain(hidden) } }
        }
    }
}

// 이 무리의 행은 모두 LMS에 아직 내지 않은 과제라 따로 표시하지 않는다.
private struct DeadlineRow: View {
    let model: LMSModel
    let deadline: LMSDeadline
    let source: Bool
    let last: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardRow(last: last) {
            LineIcon(symbol: ProposalKind.lmsAssignment.symbol).foregroundStyle(Theme.Palette.textSecondary)
            FoldingRow {
                RowText(title: deadline.assignment.title, detail: model.detail(deadline, source: source))
            } control: {
                if let due = model.due(deadline) { DueText(due: due).fixedSize() }
            }
        }
        .opens { openURL(deadline.assignment.url) }
        .accessibilityAction(named: Text(.lmsOpen)) { openURL(deadline.assignment.url) }
        .contextMenu { Button(.lmsOpen) { openURL(deadline.assignment.url) } }
    }
}

private struct DueText: View {
    let due: LMSModel.Due

    var body: some View {
        Text(due.text).font(Theme.Typeface.caption).monospacedDigit()
            .foregroundStyle(due.tone?.foreground ?? Theme.Palette.textTertiary)
    }
}
