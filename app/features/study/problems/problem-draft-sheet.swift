import FolioDomain
import SwiftUI

struct ProblemDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var model: ProblemDraftModel

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        _model = State(initialValue: ProblemDraftModel(workspace: workspace, course: course, material: material))
    }

    var body: some View {
        SheetForm(
            title: model.sheetTitle, confirm: model.confirmTitle, isDisabled: !model.canAccept, carded: false, width: Theme.Size.solveSetup,
            deleteTitle: String(localized: .problemDraftDiscard), onDelete: model.discard
        ) {
            Card {
                FormRow(label: String(localized: .problemSetFieldTitle), last: true) {
                    InlineField(String(localized: .problemSetFieldTitleExample), text: $model.title)
                }
            }
            Card {
                ScrollView {
                    VStack(spacing: 0) {
                        let lines = model.lines
                        ForEach(lines) { line in
                            let last = line.id == lines.last?.id
                            switch line {
                            case .group(let group, let depth, let leaves):
                                DraftGroupRow(
                                    group: group, depth: depth, check: model.check(leaves), caption: model.groupCaption(leaves),
                                    expanded: !model.collapsed.contains(group.id), sheet: model.sheet, accent: accent.color, last: last,
                                    toggle: { model.toggle(group: leaves) },
                                    disclose: { withAnimation(.snappy) { model.toggleCollapsed(group.id) } })
                            case .problem(let id, let depth):
                                if let i = model.index(of: id) {
                                    DraftRow(
                                        row: $model.rows[i], depth: depth, sheet: model.sheet,
                                        caption: model.caption(model.rows[i].problem),
                                        units: model.unitOptions, accent: accent.color, last: last
                                    ) {
                                        model.toggle(id)
                                    }
                                }
                            }
                        }
                    }
                }
                .overflowFade(.vertical)
                .frame(maxHeight: Theme.Size.cardDrafts)
            }
        } onConfirm: {
            if model.accept() { dismiss() }
        }
        .confirming($model.pending)
        .onChange(of: model.finished) { if model.finished { dismiss() } }
    }
}

// 받기 표시와 번호, 문제 글을 누르면 받을지 고르고, 단원은 그 옆의 칸에서 고친다. 글과 단원 칸을 `FoldingRow` 하나에 두어,
// 글이 `draftProblemText`보다 좁아지면 단원 칸이 글 아래로 내려간다.
private struct DraftRow: View {
    @Binding var row: ProblemDraftModel.Row
    let depth: Int
    let sheet: URL?
    let caption: String
    let units: [SelectOption<UUID>]
    let accent: Color
    let last: Bool
    let toggle: () -> Void

    var body: some View {
        CardRow(last: last) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Button(action: toggle) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: row.kept ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(row.kept ? accent : Theme.Palette.textTertiary).accessibilityHidden(true)
                        Text(verbatim: row.problem.number).font(Theme.Typeface.bodyStrong).monospacedDigit()
                            .frame(width: Theme.Size.solveCell, alignment: .leading)
                    }
                    .frame(minHeight: Theme.Size.touchTarget, alignment: .top)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(row.kept ? .isSelected : [])
                FoldingRow(labelRoom: Theme.Size.draftProblemText) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        ProblemStatement(problem: row.problem, sheet: sheet, lineLimit: 4)
                        Text(caption).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .contentShape(.rect)
                    .onTapGesture(perform: toggle)
                    .accessibilityAddTraits(.isButton).accessibilityAddTraits(row.kept ? .isSelected : [])
                } control: {
                    MultiCombobox(selection: $row.problem.unitIds, options: units, prompt: String(localized: .commonNone))
                        .fixedSize()
                }
            }
            .padding(.leading, CGFloat(depth) * Theme.Space.xl)
        }
    }
}

// 지문 행이다. 표시를 누르면 그 아래 문제를 모두 받거나 빼고, 오른쪽 화살표로 폴더처럼 접는다. 지문의 글과 그림은 소문제마다
// 되풀이하지 않고 여기에 한 번 보인다.
private struct DraftGroupRow: View {
    let group: ProblemGroup
    let depth: Int
    let check: ProblemDraftModel.Check
    let caption: String
    let expanded: Bool
    let sheet: URL?
    let accent: Color
    let last: Bool
    let toggle: () -> Void
    let disclose: () -> Void

    private var symbol: String {
        switch check {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }

    var body: some View {
        CardRow(last: last) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Button(action: toggle) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: symbol)
                            .foregroundStyle(check == .none ? Theme.Palette.textTertiary : accent).accessibilityHidden(true)
                        Text(verbatim: group.name).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            .frame(minWidth: Theme.Size.solveCell, alignment: .leading)
                    }
                    .frame(minHeight: Theme.Size.touchTarget, alignment: .top)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(check == .all ? .isSelected : [])
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if !group.text.isEmpty {
                        StudyText(text: group.text).lineLimit(expanded ? 4 : 1).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if expanded { ForEach(group.figures, id: \.self) { PDFRegionImage(url: sheet, region: $0) } }
                    Text(caption).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: disclose) {
                    Image(systemName: "chevron.right").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityLabel(Text(verbatim: group.name))
                .accessibilityValue(Text(expanded ? .designExpanded : .designCollapsed))
            }
            .padding(.leading, CGFloat(depth) * Theme.Space.xl)
        }
    }
}
