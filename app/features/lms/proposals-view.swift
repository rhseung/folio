import FolioDomain
import SwiftUI

/// 제안함 (#132, 시안 "LMS · 제안함"): a block per LMS classroom under its own name. Each row is added to a course
/// picked then, or dismissed; "모두 추가" adds the block's addable rows to one course as one action.
struct ProposalsView: View {
    @State private var model: ProposalsModel

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        Page(maxWidth: 760) {
            PageHeader(title: String(localized: .rootNavProposals), subtitle: model.subtitle)
            let sections = model.sections
            if sections.isEmpty {
                EmptyCard(symbol: "tray", tone: model.workspace.lms.isConnected ? .success : .plain,
                          title: String(localized: .lmsProposalsEmpty), detail: model.emptyDetail)
            }
            ForEach(sections) { section in
                Block(title: section.classroom.title, note: "\(section.proposals.count)", trailing: {
                    SectionActions(model: model, section: section)
                }) {
                    Card {
                        ForEach(Array(section.proposals.enumerated()), id: \.element.id) { i, p in
                            ProposalRow(model: model, proposal: p, last: i == section.proposals.count - 1)
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
            Button(.lmsDismissAll) { model.dismiss(section.proposals) }.buttonStyle(.pointing(.bordered))
        } else {
            TargetCourseMenu(model: model, label: String(localized: .lmsAddAll)) { course in
                Task { await model.add(addable, into: course) }
            } more: {
                Divider()
                Button(.lmsDismissAll, role: .destructive) { model.dismiss(section.proposals) }
            }
            .buttonStyle(.prominent)
            .disabled(model.isAdding(addable))
        }
    }
}

/// Which course an item goes to is picked each time: a classroom can be two of one course's, or no course at all.
private struct TargetCourseMenu<More: View>: View {
    let model: ProposalsModel
    let label: String
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
            Text(label)
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

extension TargetCourseMenu where More == EmptyView {
    init(model: ProposalsModel, label: String, pick: @escaping (UUID) -> Void) {
        self.init(model: model, label: label, pick: pick, more: { EmptyView() })
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
                    }
                    Text(model.detail(proposal)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        .truncationMode(.middle)
                }
            } control: {
                HStack(spacing: Theme.Space.s) {
                    if !model.canAdd(proposal) || proposal.key.kind == .assignment {
                        Button { openURL(proposal.url) } label: { Label(.lmsOpen, systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.pointing(.borderless))
                    }
                    Button(.lmsDismiss) { model.dismiss([proposal]) }.buttonStyle(.pointing(.borderless))
                    if model.canAdd(proposal) {
                        TargetCourseMenu(model: model, label: String(localized: .commonAdd)) { course in
                            Task { await model.add([proposal], into: course) }
                        }
                        .buttonStyle(.pointing(.bordered))
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

/// 오늘의 알림 카드: how many proposals wait, by classroom, and the way to them. Nothing when none wait.
struct LMSTodayNotice: View {
    @State private var model: ProposalsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: ProposalsModel(workspace: workspace)) }

    var body: some View {
        let sections = model.sections
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
