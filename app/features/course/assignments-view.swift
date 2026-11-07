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
                            // Not a Button: the status menu and the submit suggestion inside would lose their clicks to it.
                            CardRow(last: i == items.count - 1) { row(a, now: now) }
                                .linkTarget(a.id)
                                .opens { model.editing = a }
                                .accessibilityAction(named: Text(.commonEdit)) { model.editing = a }
                                .contextMenu {
                                    Button(.commonEditEllipsis) { model.editing = a }
                                    Menu(String(localized: .assignmentsStatus)) { statusItems(a) }
                                    LinkMenu(link: AppLink(.assignment, a.id), course: model.course.id, trailing: true)
                                    Divider()
                                    Button(.commonDeleteEllipsis, role: .destructive) { model.remove(a) }
                                }
                                .fileDrop { model.drop($0, on: a) }
                        }
                    }
                }
            }
        }
        // The jump is taken here, outside the sheet, where the course screen's target is.
        .sheet(item: $model.editing) {
            AssignmentSheet(workspace: model.workspace, course: model.course, assignment: $0) { id in
                openLink(AppLink(.material, id), course: model.course.id)
            }
        }
        .confirming($model.pending)
    }

    @ViewBuilder func statusItems(_ a: Assignment) -> some View {
        ForEach([AssignmentStatus.todo, .doing, .submitted, .graded], id: \.self) { s in
            Button { model.setStatus(a, s) } label: { Label(s.label, systemImage: s == a.status ? "checkmark" : s.symbol) }
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
        // Plain, as ChoiceMenu: a borderless menu redraws its label image at the control's size and tint, ignoring the
        // label's font and color.
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
        .help(Text(.assignmentsStatusHelp(a.status.label)))
        // The deadline in a fixed column, as the session list has its dates, so titles line up down the page.
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
                if a.repeats == .weekly { Label(.assignmentsWeekly, systemImage: "repeat") }
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

struct AssignmentSheet: View {
    @State private var model: AssignmentSheetModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickingFiles = false
    let openFile: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, assignment: Assignment, openFile: @escaping (UUID) -> Void) {
        _model = State(initialValue: AssignmentSheetModel(workspace: workspace, course: course, assignment: assignment))
        self.openFile = openFile
    }

    var body: some View {
        let files = model.files
        let scored = model.targetComponents
        let store = model.course.store
        SheetForm(title: model.sheetTitle, confirm: String(localized: .commonSave),
                  disabled: model.title.isEmpty || model.invalid,
                  carded: false, width: 560, deleteTitle: String(localized: .assignmentsDelete), onDelete: { model.delete { dismiss() } }) {
            Block(String(localized: .assignmentsSheetAssignment)) {
                Card {
                    FormRow(label: String(localized: .assignmentsFieldTitle), detail: model.titleDetail) {
                        InlineField(String(localized: .assignmentsFieldTitleExample), text: $model.title)
                    }
                    FormRow(label: String(localized: .assignmentsFieldDue)) {
                        if model.hasDue {
                            DateChip(date: $model.due)
                            Button { model.hasDue = false } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help(Text(.assignmentsClearDue))
                        } else {
                            Button(.assignmentsSetDue) { model.hasDue = true }.buttonStyle(.ghost)
                        }
                    }
                    FormRow(label: String(localized: .assignmentsFieldRepeat), detail: model.repeatDetail) {
                        ChoiceMenu(selection: $model.repeats, options: [(AssignmentRepeat?.none, String(localized: .assignmentsRepeatNever)),
                                                                        (.weekly, String(localized: .assignmentsWeekly))])
                    }
                    FormRow(label: String(localized: .assignmentsStatus), last: true) {
                        ChoiceMenu(selection: $model.status, options: [AssignmentStatus.todo, .doing, .submitted, .graded].map { ($0, $0.label) })
                    }
                }
            }
            Block(String(localized: .assignmentsScore), note: String(localized: .assignmentsScoreNote)) {
                Card {
                    FormRow(label: String(localized: .assignmentsFieldTarget), last: scored.isEmpty) {
                        SearchSelect(selection: Binding(get: { model.target }, set: { model.pick($0) }), options: model.targetOptions)
                    }
                    ForEach(Array(scored.enumerated()), id: \.element.id) { i, c in
                        FormRow(label: scored.count > 1 ? c.name : String(localized: .assignmentsScore), last: i == scored.count - 1) {
                            TextField(String(localized: .assignmentsScore), text: Binding(get: { model.scores[c.id] ?? "" }, set: { model.scores[c.id] = $0 })).pill(width: 72)
                            Text("/").foregroundStyle(Theme.Palette.textTertiary)
                            TextField(String(localized: .assignmentsMax), text: Binding(get: { model.maxes[c.id] ?? "" }, set: { model.maxes[c.id] = $0 })).pill(width: 72)
                        }
                    }
                }
                .sensitive(scored.isEmpty ? nil : .block)
            }
            FormTextArea(label: String(localized: .assignmentsMemo), text: $model.memo, height: 56)
            Block(title: String(localized: .assignmentsFiles), note: model.folder) {
                Button(.assignmentsAddFiles) { pickingFiles = true }
                    .buttonStyle(.ghost)
                    .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        if case .success(let urls) = result { model.importFiles(urls) }
                    }
            } content: {
                Card {
                    if files.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .assignmentsFilesEmpty)) } }
                    ForEach(Array(files.enumerated()), id: \.element.id) { i, m in
                        let name = (m.path as NSString).lastPathComponent
                        let kind = model.kind(of: m)
                        CardRow(last: i == files.count - 1) {
                            Group {
                                Image(systemName: kind == .submission ? "paperplane" : "doc").foregroundStyle(Theme.Palette.textSecondary)
                                Text(name).lineLimit(1)
                            }
                            .fileDrag(store.fileURL(m.path))
                            Spacer()
                            ChoiceMenu(selection: Binding(get: { kind }, set: { model.setKind(m, $0) }), options: model.kindOptions)
                            if model.opens(m) { Button(.assignmentsOpen) { open(m) }.buttonStyle(.ghost) }
                        }
                        .contentShape(.rect)
                        .contextMenu { if model.opens(m) { Button(.assignmentsOpen) { open(m) } } }
                    }
                }
                .fileDrop { model.importFiles($0) }
            }
        } onConfirm: {
            if model.apply() { dismiss() }
        }
        .confirming($model.pending)
        .confirmationDialog(String(localized: .assignmentsOpenUnsaved), isPresented: asking, titleVisibility: .visible, presenting: model.opening) { m in
            Button(.assignmentsOpenSave) { if model.saveAndOpen() { show(m.id) } }
            Button(.assignmentsOpenDiscard, role: .destructive) {
                model.discardAndOpen()
                show(m.id)
            }
            Button(.commonCancel, role: .cancel) { model.opening = nil }
        } message: { _ in
            Text(.assignmentsOpenUnsavedMessage)
        }
        .onAppear { model.load() }
    }

    var asking: Binding<Bool> {
        Binding(get: { model.opening != nil }, set: { if !$0 { model.opening = nil } })
    }

    func open(_ m: FolioDomain.Material) {
        switch model.open(m) {
        case .elsewhere(let url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        case .materials(let id): show(id)
        case .asks: break
        }
    }

    func show(_ id: UUID) {
        dismiss()
        openFile(id)
    }
}
