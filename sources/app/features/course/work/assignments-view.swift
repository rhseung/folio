import FolioDomain
import SwiftUI

struct AssignmentsView: View {
    @State private var model: AssignmentsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: AssignmentsModel(workspace: workspace, course: course))
    }

    var body: some View {
        let now = model.workspace.now
        let course = model.course
        Page {
            PageHeader(title: String(localized: .assignmentsTitle), subtitle: model.subtitle)
            QuickAddField(workspace: model.workspace, fixedCourse: course.id)
            if course.file.assignments.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .assignmentsEmpty)) } }
            }
            ForEach(model.groups(now: now), id: \.group) { g, items in
                Block(g.label, note: "\(items.count)") {
                    Card {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                            // Button으로 두면 안의 상태 메뉴와 제출 제안이 클릭을 빼앗긴다.
                            CardRow(last: i == items.count - 1) { row(a, now: now) }
                                .linkTarget(a.id)
                                .opens { model.editing = a }
                                .accessibilityAction(named: Text(.commonEdit)) { model.editing = a }
                                .contextMenu { AssignmentMenu(courseId: model.course.id, assignmentId: a.id, host: .own) }
                                .fileDrop { model.drop($0, on: a) }
                        }
                    }
                }
            }
        }
        .sheet(item: $model.editing) {
            AssignmentSheet(workspace: model.workspace, course: model.course, assignment: $0) { id, placement in
                openLink(AppLink(.material, id), in: placement, course: model.course.id)
            }
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.editAssignmentMemo, initial: true) { _, memo in
            model.editing = memo.flatMap { memo in
                model.course.file.assignments.first.map {
                    var a = $0; a.memo = memo; return a
                }
            }
        }
        #endif
        .confirming($model.pending)
    }

    @ViewBuilder func statusItems(_ a: Assignment) -> some View {
        ForEach(AssignmentStatus.menuOrder, id: \.self) { s in
            Button {
                model.setStatus(a, s)
            } label: {
                Label(s.label, systemImage: s == a.status ? "checkmark" : s.symbol)
            }
        }
    }

    @ViewBuilder func row(_ a: Assignment, now: Date) -> some View {
        let row = model.row(a)
        let due = model.due(a)
        let done = !a.status.isOpen
        Menu {
            statusItems(a)
        } label: {
            AssignmentStatusIcon(status: a.status)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: a.status)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        // borderless 메뉴는 라벨 이미지를 컨트롤의 크기와 색으로 다시 그리고 라벨의 글꼴과 색을 무시하므로,
        // ChoiceMenu처럼 plain으로 둔다.
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
        .help(Text(.assignmentsStatusHelp(a.status.label)))
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(due.date).font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(a.due == nil || done ? Theme.Palette.textTertiary : Theme.Palette.text)
            if let time = due.time {
                Text(time)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            }
        }
        .frame(width: 84, alignment: .leading)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                .strikethrough(done, color: Theme.Palette.textTertiary)
                .foregroundStyle(done ? Theme.Palette.textTertiary : Theme.Palette.text)
                .animation(.easeOut(duration: 0.25), value: done)
            let meta = HStack(spacing: Theme.Space.s) {
                if let repeats = a.repeats { Label(repeats.label, systemImage: "repeat") }
                if row.problems > 0 { Label(.assignmentsProblems(row.problems), systemImage: "doc") }
                if row.submissions > 0 { Label(.assignmentsSubmissions(row.submissions), systemImage: "paperplane") }
                if let component = row.component { Label(component, systemImage: "chart.pie") }
                if !a.memo.isEmpty { Image(systemName: "text.alignleft").accessibilityLabel(Text(.assignmentsMemo)) }
            }
            meta.labelStyle(.titleAndIcon).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if row.suggestsSubmitted {
            Button(.assignmentsSuggestSubmitted) { model.setStatus(a, .submitted) }.buttonStyle(.pointing(.bordered))
        }
        if let score = row.score {
            Chip(score, tone: .accent).sensitive()
        }
        if let chip = model.dueChip(a, now: now) { Chip(chip.text, tone: chip.tone) }
    }
}
