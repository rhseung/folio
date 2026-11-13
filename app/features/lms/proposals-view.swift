import FolioDomain
import SwiftUI

/// 제안함 (#132, 시안 "LMS · 제안함"). Hidden items stay folded under each classroom so a dismissal made by mistake can
/// be taken back.
struct ProposalsView: View {
    @State private var model: ProposalsModel

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .rootNavProposals), subtitle: model.subtitle)
            if model.inbox.isEmpty {
                EmptyCard(
                    symbol: "tray", tone: model.workspace.lms.isConnected ? .success : .plain,
                    title: String(localized: .lmsProposalsEmpty), detail: model.emptyDetail)
            }
            ForEach(model.sections) { section in
                Block(
                    title: section.classroom.title, note: model.count(section),
                    trailing: {
                        if !section.proposals.isEmpty { SectionActions(model: model, section: section) }
                    }
                ) {
                    Card {
                        ForEach(section.proposals) { p in
                            ProposalRow(model: model, proposal: p, last: model.isLast(p, in: section))
                        }
                        if !section.handled.isEmpty {
                            DisclosureRow(
                                label: String(localized: .lmsHidden(section.handled.count)),
                                isOpen: Binding(
                                    get: { model.showsHandled(section) }, set: { _ in model.toggleHandled(section) }), last: true
                            ) {
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
    var strong = false
    let pick: (UUID) -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        Menu {
            Section(String(localized: .lmsAddTo)) {
                ForEach(model.targets, id: \.id) { course in
                    Button {
                        pick(course.id)
                    } label: {
                        Text(course.title)
                    }
                }
            }
            more()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(label)
                Image(systemName: "chevron.down").font(Theme.Glyph.small).accessibilityHidden(true)
            }
        }
        .menuStyle(.button).buttonStyle(SoftButtonStyle(strong: strong)).menuIndicator(.hidden)
        .fixedSize()
    }
}

extension TargetCourseMenu where More == EmptyView {
    init(model: ProposalsModel, label: String, strong: Bool = false, pick: @escaping (UUID) -> Void) {
        self.init(model: model, label: label, strong: strong, pick: pick, more: { EmptyView() })
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
                    if model.showsOpen(proposal) {
                        Button {
                            openURL(proposal.url)
                        } label: {
                            Label(.lmsOpen, systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(SoftButtonStyle(iconOnly: true)).help(String(localized: .lmsOpen))
                    }
                    Button(.lmsDismiss) { model.dismiss([proposal]) }.buttonStyle(SoftButtonStyle())
                    if model.canAdd(proposal) {
                        TargetCourseMenu(model: model, label: String(localized: .commonAdd), strong: true) { course in
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
                    Button {
                        openURL(handled.proposal.url)
                    } label: {
                        Label(.lmsOpen, systemImage: "arrow.up.forward.app")
                    }
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
/// tinted words read as one blue line, and a blue add was too loud again. All gray; the one add per row is set apart by
/// darker, bolder words.
private struct SoftButtonStyle: ButtonStyle {
    var strong = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration, strong: strong, iconOnly: iconOnly)
    }
}

private struct SoftButton: View {
    let configuration: ButtonStyleConfiguration
    let strong: Bool
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
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
        .font(strong ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
        .lineLimit(1)
        .foregroundStyle(strong ? Theme.Palette.text : Theme.Palette.textSecondary)
        .background(Theme.Palette.textSecondary.opacity(strength), in: .capsule)
        .contentShape(TouchTarget())
        .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
        #endif
    }
}

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
