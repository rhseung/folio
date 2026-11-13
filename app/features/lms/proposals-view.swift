import FolioDomain
import SwiftUI

/// 제안함 (#132, 시안 "LMS · 제안함"): a block per LMS classroom under its own name. Each row is added to a course
/// picked then, or dismissed; "모두 추가" adds the block's addable rows to one course as one action. Under them, folded,
/// what the classroom has that was handled, so a dismissal made by mistake can be proposed again.
struct ProposalsView: View {
    @State private var model: ProposalsModel

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .rootNavProposals), subtitle: model.subtitle)
            let sections = model.sections
            if model.inbox.isEmpty {
                EmptyCard(symbol: "tray", tone: model.workspace.lms.isConnected ? .success : .plain,
                          title: String(localized: .lmsProposalsEmpty), detail: model.emptyDetail)
            }
            ForEach(sections) { section in
                Block(title: section.classroom.title, note: section.proposals.isEmpty ? nil : "\(section.proposals.count)", trailing: {
                    if !section.proposals.isEmpty { SectionActions(model: model, section: section) }
                }) {
                    Card {
                        ForEach(section.proposals) { p in
                            ProposalRow(model: model, proposal: p, last: section.handled.isEmpty && p.id == section.proposals.last?.id)
                        }
                        if !section.handled.isEmpty {
                            DisclosureRow(label: String(localized: .lmsHandled(section.handled.count)), isOpen: Binding(
                                get: { model.showsHandled(section) }, set: { _ in model.toggleHandled(section) }), last: true) {
                                ForEach(section.handled) { h in
                                    HandledRow(model: model, handled: h, last: h.id == section.handled.last?.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// "모두 추가 ⌄" holds the courses and, under them, "모두 무시"; a classroom with only notices has just "모두 무시".
private struct SectionActions: View {
    let model: ProposalsModel
    let section: LMSInbox.Section

    var body: some View {
        let addable = model.addable(section)
        if addable.isEmpty {
            Button(.lmsDismissAll) { model.dismiss(section.proposals) }.buttonStyle(SoftButtonStyle())
        } else {
            TargetCourseMenu(model: model, label: String(localized: .lmsAddAll)) { course in
                Task { await model.add(addable, into: course) }
            } more: {
                Divider()
                Button(.lmsDismissAll, role: .destructive) { model.dismiss(section.proposals) }
            }
            .disabled(model.isAdding(addable))
        }
    }
}

/// Which course an item goes to is picked each time: a classroom can be two of one course's, or no course at all.
private struct TargetCourseMenu<More: View>: View {
    let model: ProposalsModel
    let label: String
    var accent = false
    let pick: (UUID) -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        Menu {
            Section(String(localized: .lmsAddTo)) {
                ForEach(model.targets, id: \.id) { course in
                    Button { pick(course.id) } label: { Text(course.title) }
                }
            }
            more()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(label)
                Image(systemName: "chevron.down").font(Theme.Glyph.small)
            }
        }
        .menuStyle(.button).buttonStyle(SoftButtonStyle(accent: accent)).menuIndicator(.hidden)
        .fixedSize()
    }
}

extension TargetCourseMenu where More == EmptyView {
    init(model: ProposalsModel, label: String, accent: Bool = false, pick: @escaping (UUID) -> Void) {
        self.init(model: model, label: label, accent: accent, pick: pick, more: { EmptyView() })
    }
}

/// The buttons sit beside the title where they fit and fold under it where they don't (a phone's width).
private struct ProposalRow: View {
    let model: ProposalsModel
    let proposal: LMSProposal
    let last: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardRow(last: last) {
            LineIcon(symbol: model.symbol(proposal)).foregroundStyle(Theme.Palette.textSecondary)
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(proposal.title).lineLimit(2)
                        if model.isViewerOnly(proposal) { Chip(String(localized: .lmsViewerOnly), tone: .warning) }
                        if let due = model.due(proposal) { DueChip(text: due.text, urgency: due.urgency) }
                    }
                    Text(model.detail(proposal)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        .truncationMode(.middle)
                }
            } control: {
                HStack(spacing: Theme.Space.s) {
                    if !model.canAdd(proposal) || proposal.key.kind == .assignment {
                        Button { openURL(proposal.url) } label: { Label(.lmsOpen, systemImage: "arrow.up.forward.app") }
                            .buttonStyle(SoftButtonStyle(iconOnly: true)).help(String(localized: .lmsOpen))
                    }
                    Button(.lmsDismiss) { model.dismiss([proposal]) }.buttonStyle(SoftButtonStyle())
                    if model.canAdd(proposal) {
                        TargetCourseMenu(model: model, label: String(localized: .commonAdd), accent: true) { course in
                            Task { await model.add([proposal], into: course) }
                        }
                        .disabled(model.isAdding([proposal]))
                    }
                }
                .fixedSize()
            }
        }
        .contextMenu {
            Button(.lmsOpen) { openURL(proposal.url) }
            Button(.lmsDismiss) { model.dismiss([proposal]) }
        }
    }
}

/// A handled item: open in the LMS, or proposed again. An assignment already in a course only says which.
private struct HandledRow: View {
    let model: ProposalsModel
    let handled: LMSInbox.Handled
    let last: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardRow(last: last) {
            LineIcon(symbol: model.symbol(handled.proposal)).foregroundStyle(Theme.Palette.textTertiary)
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(handled.proposal.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    Text(model.detail(handled)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        .truncationMode(.middle)
                }
            } control: {
                HStack(spacing: Theme.Space.s) {
                    Button { openURL(handled.proposal.url) } label: { Label(.lmsOpen, systemImage: "arrow.up.forward.app") }
                        .buttonStyle(SoftButtonStyle(iconOnly: true)).help(String(localized: .lmsOpen))
                    if model.canProposeAgain(handled) {
                        Button(.lmsRestore) { model.proposeAgain(handled) }.buttonStyle(SoftButtonStyle())
                    }
                }
                .fixedSize()
            }
        }
        .contextMenu {
            Button(.lmsOpen) { openURL(handled.proposal.url) }
            if model.canProposeAgain(handled) { Button(.lmsRestore) { model.proposeAgain(handled) } }
        }
    }
}

/// Today's list's chip, so a deadline reads the same before and after it is added: filled on the last day, toned within
/// the week, plain past it.
private struct DueChip: View {
    let text: String
    let urgency: DueUrgency

    var body: some View {
        switch urgency {
        case .urgent: Chip(text, tone: .danger, solid: true).monospacedDigit()
        case .soon: Chip(text, tone: .warning).monospacedDigit()
        case .later: Chip(text).monospacedDigit()
        }
    }
}

/// 제안함's buttons are filled capsules, not the app's ghost text (#132, decided for this screen only): a row of three
/// tinted words read as one blue line. Gray for the side actions, the course accent for the one add per row.
private struct SoftButtonStyle: ButtonStyle {
    var accent = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration, accent: accent, iconOnly: iconOnly)
    }
}

private struct SoftButton: View {
    let configuration: ButtonStyleConfiguration
    let accent: Bool
    let iconOnly: Bool
    @Environment(\.accent) private var courseAccent
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        // `.gray` is the accent where no course is in view, and 제안함 is outside every course: the add would read as one more
        // gray button, so it takes the app's accent as `.prominent` does.
        let tint: Color = courseAccent == .gray ? .accentColor : courseAccent.color
        let ink: Color = accent ? (courseAccent == .gray ? .accentColor : courseAccent.ink) : Theme.Palette.textSecondary
        let fill: Color = accent ? tint : Theme.Palette.textSecondary
        let strength = Theme.Opacity.tint * (configuration.isPressed ? 2 : hovering && isEnabled ? 1.5 : 1)
        Group {
            if iconOnly {
                configuration.label.labelStyle(.iconOnly)
                    .frame(width: Theme.Space.xl + Theme.Space.xs, height: Theme.Space.xl + Theme.Space.xs)
            } else {
                configuration.label
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.xs + Theme.Space.xxs)
            }
        }
        .font(accent ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
        .lineLimit(1)
        .foregroundStyle(ink)
        .background(fill.opacity(strength), in: .capsule)
        .contentShape(TouchTarget())
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
        #endif
    }
}

/// 오늘의 알림 카드: how many proposals wait, by classroom, and the way to them. Nothing when none wait.
struct LMSTodayNotice: View {
    @State private var model: ProposalsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        let sections = model.waiting
        if !sections.isEmpty {
            NoticeCard(title: String(localized: .lmsTodayTitle(model.total)), detail: model.earliestDue, systemImage: "tray") {
                Button(.lmsOpenProposals) { openLink(.place(.proposals)) }.buttonStyle(.prominent)
            } rows: {
                ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                    CardRow(last: i == sections.count - 1) {
                        Text(section.classroom.title).lineLimit(1)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(section.proposals.count)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
    }
}
