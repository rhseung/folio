import FolioActions
import FolioDomain
import SwiftUI

struct AssignmentsView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    @State private var editing: Assignment?
    @State private var deleting: Assignment?

    enum Group: String, CaseIterable {
        case overdue = "마감 지남", open = "진행 중", submitted = "제출함", graded = "채점됨"
    }

    var body: some View {
        let file = course.file
        let now = Date.now
        let grouped = Dictionary(grouping: file.assignments) { group(of: $0, now: now) }
        Page {
            let open = file.assignments.filter(\.status.isOpen)
            PageHeader(title: "과제", subtitle: (["과제 \(file.assignments.count)개"] + (open.isEmpty ? [] : ["남은 과제 \(open.count)개"])
                                                 + (open.contains { $0.due == nil } ? ["마감 없음 \(open.filter { $0.due == nil }.count)개"] : [])).joined(separator: " · "))
            QuickAddField(workspace: workspace, fixedCourse: course.id)
            if file.assignments.isEmpty {
                Card { CardRow(last: true) { EmptyLine("과제가 없습니다. 위에서 한 줄로 추가하거나, Assignments 폴더를 만들면 여기에 생깁니다.") } }
            }
            ForEach(Group.allCases, id: \.self) { g in
                let items = sorted(grouped[g] ?? [], group: g)
                if !items.isEmpty {
                    Block(g.rawValue, note: "\(items.count)") {
                        Card {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                                // Not a Button: the status menu and the submit suggestion inside would lose their clicks to it.
                                CardRow(last: i == items.count - 1) { row(a, now: now) }
                                    .opens { editing = a }
                                    .accessibilityAction(named: "편집") { editing = a }
                                    .contextMenu {
                                        Button("편집…") { editing = a }
                                        Menu("상태") { statusItems(a) }
                                        Divider()
                                        Button("삭제…", role: .destructive) { deleting = a }
                                    }
                                    .fileDrop { workspace.importFiles($0, into: AssignmentFiles.path(of: a), course: course.id) }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { AssignmentSheet(course: course, assignment: $0) }
        .confirmationDialog("\(deleting?.title ?? "")을 지울까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { a in
            Button("삭제", role: .destructive) { workspace.run(AssignmentRemove(course: course.id, assignment: a.id)) }
        } message: { _ in
            Text("과제 항목과 연결된 점수만 지웁니다. 폴더와 파일은 그대로 둡니다.")
        }
    }

    @ViewBuilder func statusItems(_ a: Assignment) -> some View {
        ForEach([AssignmentStatus.todo, .doing, .submitted, .graded], id: \.self) { s in
            Button { setStatus(a, s) } label: { Label(s.label, systemImage: s == a.status ? "checkmark" : s.symbol) }
        }
    }

    func group(of a: Assignment, now: Date) -> Group {
        switch a.status {
        case .graded: .graded
        case .submitted: .submitted
        case .todo, .doing: (a.due.map { $0 < now } ?? false) ? .overdue : .open
        }
    }

    func sorted(_ items: [Assignment], group: Group) -> [Assignment] {
        switch group {
        case .overdue, .open: items.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        case .submitted, .graded: items.sorted { ($0.due ?? .distantPast, $0.title) > ($1.due ?? .distantPast, $1.title) }
        }
    }

    @ViewBuilder func row(_ a: Assignment, now: Date) -> some View {
        let files = AssignmentFiles.materials(of: a, in: course.file.materials)
        let submissions = files.filter { ($0.kind ?? AssignmentFiles.guessKind(fileName: ($0.path as NSString).lastPathComponent)) == .submission }.count
        // A group-scored assignment has one entry per component; the row shows their total.
        let scores = course.file.scores.filter { $0.assignmentId == a.id }
        let component = a.componentGroup ?? course.file.components.first { $0.id == a.componentId }?.name
        let done = !a.status.isOpen
        Menu {
            statusItems(a)
        } label: {
            Image(systemName: a.status.symbol)
                .font(.system(size: 20)) // design: one-off, the status symbol is the row's button
                .foregroundStyle(a.status == .todo ? Theme.Palette.textTertiary : a.status.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: a.status)
                .frame(width: 24, height: 24).contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        // Plain, as ChoiceMenu: a borderless menu redraws its label image at the control's size and tint, ignoring the
        // label's font and color.
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
        .help("상태: \(a.status.label)")
        // The deadline in a fixed column, as the session list has its dates, so titles line up down the page.
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(a.due?.formatted(.dateTime.month().day()) ?? "마감 없음").font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(a.due == nil || done ? Theme.Palette.textTertiary : Theme.Palette.text)
            if let due = a.due {
                Text(due.formatted(.dateTime.weekday()) + " " + TimeMenu.label(workspace.calendar.component(.hour, from: due) * 60 + workspace.calendar.component(.minute, from: due)))
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
                if a.repeats == .weekly { Label("매주", systemImage: "repeat") }
                if files.count > submissions { Label("문제 \(files.count - submissions)", systemImage: "doc") }
                if submissions > 0 { Label("제출본 \(submissions)", systemImage: "paperplane") }
                if let component { Label(component, systemImage: "chart.pie") }
                if !a.memo.isEmpty { Image(systemName: "text.alignleft").accessibilityLabel("메모") }
            }
            meta.labelStyle(.titleAndIcon).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if AssignmentFiles.suggestsSubmitted(a, files: files) {
            Button("제출본 있음 · 제출로") { setStatus(a, .submitted) }.buttonStyle(.pointing(.bordered))
        }
        if !scores.isEmpty {
            Chip("\(scores.map(\.score).reduce(0, +).formatted())/\(scores.map(\.max).reduce(0, +).formatted())", tone: .accent).sensitive()
        }
        dueChip(a, now: now)
    }

    @ViewBuilder func dueChip(_ a: Assignment, now: Date) -> some View {
        if a.status.isOpen {
            switch DueState(due: a.due, now: now, calendar: workspace.calendar) {
            case .none: EmptyView()
            case .overdue(let d): Chip(d == 0 ? "방금 지남" : "\(d)일 지남", tone: .danger)
            case .hours(let h): Chip("\(h)시간 남음", tone: .danger)
            case .days(let d): Chip("D-\(d)", tone: d <= 3 ? .warning : .plain)
            }
        }
    }

    func setStatus(_ a: Assignment, _ status: AssignmentStatus) {
        workspace.run(AssignmentStatusSet(course: course.id, assignment: a.id, status: status))
    }
}

enum ScoreTarget: Hashable {
    case none, component(UUID), group(String)
}

struct AssignmentSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    let assignment: Assignment
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date.now
    @State private var status: AssignmentStatus = .todo
    @State private var repeats: AssignmentRepeat?
    @State private var target = ScoreTarget.none
    /// Typed score and max per component, so switching the target keeps what was typed.
    @State private var scores: [UUID: String] = [:]
    @State private var maxes: [UUID: String] = [:]
    @State private var memo = ""
    @State private var confirmingDelete = false
    @State private var pickingFiles = false

    var body: some View {
        let files = AssignmentFiles.materials(of: assignment, in: course.file.materials)
        let scored = targetComponents
        let invalid = scored.contains { c in !(scores[c.id] ?? "").isEmpty && (Double(scores[c.id] ?? "") == nil || (Double(maxes[c.id] ?? "") ?? 0) <= 0) }
        SheetForm(title: "\(assignment.title) 편집", confirm: "저장",
                  disabled: title.isEmpty || invalid,
                  carded: false, width: 560, deleteTitle: "과제 삭제", onDelete: { confirmingDelete = true }) {
            Block("과제") {
                Card {
                    let folder = AssignmentFiles.path(of: Assignment(device: workspace.device, at: .now, title: title))
                    // The files are found by the folder the title names, so a title naming another folder loses them here.
                    FormRow(label: "제목", detail: folder == AssignmentFiles.path(of: assignment) || files.isEmpty ? nil : "\(folder) 폴더의 파일을 보게 됩니다. 파일은 옮기지 않습니다") {
                        InlineField("예: HW 5", text: $title)
                    }
                    FormRow(label: "마감") {
                        if hasDue {
                            DateChip(date: $due)
                            Button { hasDue = false } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help("마감 지우기")
                        } else {
                            Button("마감 정하기") { hasDue = true }.buttonStyle(.ghost)
                        }
                    }
                    FormRow(label: "반복", detail: repeats != .weekly ? nil : hasDue ? "제출로 바꾸면 다음 주 같은 시각의 과제가 생깁니다" : "마감을 정해야 다음 과제가 생깁니다") {
                        ChoiceMenu(selection: $repeats, options: [(AssignmentRepeat?.none, "안 함"), (.weekly, "매주")])
                    }
                    FormRow(label: "상태", last: true) {
                        ChoiceMenu(selection: $status, options: [AssignmentStatus.todo, .doing, .submitted, .graded].map { ($0, $0.label) })
                    }
                }
            }
            Block("점수", note: "넣으면 고른 평가 항목의 점수가 됩니다") {
                Card {
                    FormRow(label: "평가 항목", last: scored.isEmpty) {
                        SearchSelect(selection: Binding(get: { target }, set: { pick($0) }), options: targetOptions)
                    }
                    ForEach(Array(scored.enumerated()), id: \.element.id) { i, c in
                        FormRow(label: scored.count > 1 ? c.name : "점수", last: i == scored.count - 1) {
                            TextField("점수", text: binding(\.scores, c.id)).pill(width: 72)
                            Text("/").foregroundStyle(Theme.Palette.textTertiary)
                            TextField("만점", text: binding(\.maxes, c.id)).pill(width: 72)
                        }
                    }
                }
                .sensitive(scored.isEmpty ? nil : .block)
            }
            FormTextArea(label: "메모", text: $memo, height: 56)
            Block(title: "파일", note: AssignmentFiles.path(of: assignment)) {
                Button("파일 추가") { pickingFiles = true }
                    .buttonStyle(.ghost)
                    .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        if case .success(let urls) = result { workspace.importFiles(urls, into: AssignmentFiles.path(of: assignment), course: course.id) }
                    }
            } content: {
                Card {
                    if files.isEmpty { CardRow(last: true) { EmptyLine("폴더에 파일이 없습니다. 여기에 끌어다 놓거나 파일 추가로 넣으세요.") } }
                    ForEach(Array(files.enumerated()), id: \.element.id) { i, m in
                        let name = (m.path as NSString).lastPathComponent
                        let kind = m.kind ?? AssignmentFiles.guessKind(fileName: name)
                        CardRow(last: i == files.count - 1) {
                            Group {
                                Image(systemName: kind == .submission ? "paperplane" : "doc").foregroundStyle(Theme.Palette.textSecondary)
                                Text(name).lineLimit(1)
                            }
                            .fileDrag(course.store.fileURL(m.path))
                            Spacer()
                            Chip(kind == .submission ? "제출본" : "문제")
                            #if os(macOS)
                            Button("열기") { NSWorkspace.shared.open(course.store.fileURL(m.path)) }.buttonStyle(.ghost)
                            #endif
                        }
                        #if os(macOS)
                        .contentShape(.rect)
                        .contextMenu { Button("열기") { NSWorkspace.shared.open(course.store.fileURL(m.path)) } }
                        #endif
                    }
                }
                .fileDrop { workspace.importFiles($0, into: AssignmentFiles.path(of: assignment), course: course.id) }
            }
        } onConfirm: {
            save()
        }
        .confirmationDialog("\(assignment.title)을 지울까요?", isPresented: $confirmingDelete) {
            Button("삭제", role: .destructive) { delete() }
        } message: {
            Text("과제 항목과 연결된 점수만 지웁니다. 폴더와 파일은 그대로 둡니다.")
        }
        .onAppear(perform: load)
    }

    var sortedComponents: [GradeComponent] { course.file.components.sorted { $0.order < $1.order } }

    var targetComponents: [GradeComponent] {
        switch target {
        case .none: []
        case .component(let id): sortedComponents.filter { $0.id == id }
        case .group(let g): sortedComponents.filter { $0.group == g }
        }
    }

    // A group heads its components, indented under it, so picking the whole group or one part reads as a tree.
    var targetOptions: [PickOption<ScoreTarget>] {
        var options = [PickOption(id: ScoreTarget.none, title: "없음")]
        var seen = Set<String>()
        for c in sortedComponents {
            guard let g = c.group else { options.append(PickOption(id: .component(c.id), title: c.name)); continue }
            guard seen.insert(g).inserted else { continue }
            let members = sortedComponents.filter { $0.group == g }
            options.append(PickOption(id: .group(g), title: "\(g) 전체", detail: "\(members.count)개 항목에 하나씩"))
            options += members.map { PickOption(id: .component($0.id), title: $0.name, depth: 1) }
        }
        return options
    }

    func binding(_ key: ReferenceWritableKeyPath<Self, [UUID: String]>, _ id: UUID) -> Binding<String> {
        Binding(get: { self[keyPath: key][id] ?? "" }, set: { self[keyPath: key][id] = $0 })
    }

    /// A component without a typed max takes the one its last score had, as a weekly report is out of the same points.
    func pick(_ t: ScoreTarget) {
        target = t
        for c in targetComponents where (maxes[c.id] ?? "").isEmpty {
            maxes[c.id] = course.file.scores.last { $0.componentId == c.id }?.max.formatted()
        }
    }

    func load() {
        title = assignment.title
        hasDue = assignment.due != nil
        due = assignment.due ?? workspace.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
        status = assignment.status
        repeats = assignment.repeats
        memo = assignment.memo
        let own = course.file.scores.filter { $0.assignmentId == assignment.id }
        for s in own {
            scores[s.componentId] = s.score.formatted()
            maxes[s.componentId] = s.max.formatted()
        }
        target = assignment.componentGroup.map { .group($0) } ?? (assignment.componentId ?? own.first?.componentId).map { .component($0) } ?? .none
    }

    func save() {
        let scored = targetComponents
        let entered = scored.compactMap { c -> AssignmentSave.Score? in
            guard let s = Double(scores[c.id] ?? ""), let m = Double(maxes[c.id] ?? ""), m > 0 else { return nil }
            return AssignmentSave.Score(component: c.id, score: s, max: m)
        }
        var componentId: UUID?, group: String?
        if case .component(let id) = target { componentId = id }
        if case .group(let g) = target { group = g }
        guard workspace.run(AssignmentSave(course: course.id, assignment: assignment.id, title: title, due: hasDue ? due : nil, status: status,
                                           repeats: repeats, componentId: componentId, componentGroup: group, memo: memo,
                                           components: scored.map(\.id), scores: entered)) != nil else { return }
        dismiss()
    }

    func delete() {
        workspace.run(AssignmentRemove(course: course.id, assignment: assignment.id))
        dismiss()
    }
}
