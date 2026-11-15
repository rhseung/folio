import FolioDomain
import SwiftUI

struct ProposalsView: View {
    @State private var model: ProposalsModel

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .rootNavProposals), subtitle: model.subtitle)
            if model.inbox.isEmpty {
                EmptyCard(
                    systemImage: "tray", tone: model.workspace.lms.isConnected ? .success : .plain,
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
                                isExpanded: Binding(
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
            Button(.lmsDismissAll) { model.dismiss(section.proposals) }.buttonStyle(.secondary)
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
                        if model.isViewerOnly(proposal) { Badge(String(localized: .lmsViewerOnly), tone: .warning) }
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
                        .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
                    }
                    Button(.lmsDismiss) { model.dismiss([proposal]) }.buttonStyle(.secondary)
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
                    .buttonStyle(.secondary(iconOnly: true)).help(String(localized: .lmsOpen))
                    if model.canProposeAgain(handled) {
                        Button(.lmsRestore) { model.proposeAgain(handled) }.buttonStyle(.secondary)
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
