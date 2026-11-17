import FolioDomain
import SwiftUI

struct AssignmentsView: View {
    @State private var model: AssignmentsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: AssignmentsModel(workspace: workspace, course: course))
    }

    var body: some View {
        // 분 단위로 세는 마감이 시계를 따라 바뀌도록 매분 바뀌는 시각을 읽는다.
        let now = model.workspace.liveNow
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
        let due = model.due(a, now: now)
        let done = !a.status.isOpen
        Menu {
            statusItems(a)
        } label: {
            AssignmentStatusIcon(status: a.status)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: a.status)
                .contentShape(.rect)
        }
        .menuButton(indicator: .hidden)
        .fixedSize()
        .help(Text(.assignmentsStatusHelp(a.status.label)))
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(due.date).font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(a.due == nil || done ? Theme.Palette.textTertiary : due.tone.foreground)
            if let time = due.time {
                Text(time)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            }
        }
        .frame(width: Theme.Size.dateColumn, alignment: .leading)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                .strikethrough(done, color: Theme.Palette.textTertiary)
                .foregroundStyle(done ? Theme.Palette.textTertiary : Theme.Palette.text)
                .animation(Theme.Motion.standard, value: done)
            // 좁은 폭에서는 줄 끝이 잘리므로 LMS 표시를 맨 앞에 두고 먼저 자리를 준다. 고정 폭으로 두면 화면이 넘친다.
            let meta = HStack(spacing: Theme.Space.s) {
                if row.lms { Label(.assignmentsLms, systemImage: "link").layoutPriority(1) }
                if let repeats = a.repeats { Label(repeats.label, systemImage: "repeat") }
                if let submitted = row.submittedOn {
                    Label(submitted, systemImage: "paperplane")
                        .foregroundStyle(row.lateSubmitted ? Theme.Palette.danger : Theme.Palette.textTertiary)
                } else if row.submissions > 0 {
                    Label(.assignmentsSubmissions(row.submissions), systemImage: "paperplane")
                }
                if row.problems > 0 { Label(.assignmentsProblems(row.problems), systemImage: "doc") }
                if let component = row.component { Label(component, systemImage: "chart.pie") }
                if !a.memo.isEmpty { Image(systemName: "text.alignleft").accessibilityLabel(Text(.assignmentsMemo)) }
            }
            // 아이콘은 줄어들지 않아서, 긴 뱃지 옆에서는 줄의 최소 폭이 행을 넘친다. 자리가 없으면 줄을 자른다.
            meta.labelStyle(.titleAndIcon).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                .frame(minWidth: 0, alignment: .leading).clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let score = row.score {
            Badge(score, tone: .accent).sensitive()
        }
    }
}
