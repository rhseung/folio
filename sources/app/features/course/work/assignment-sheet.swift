import FolioDomain
import SwiftUI

struct AssignmentSheet: View {
    @State private var model: AssignmentSheetModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickingFiles = false
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    let openFile: (UUID, LinkPlacement) -> Void

    init(workspace: Workspace, course: LoadedCourse, assignment: Assignment, openFile: @escaping (UUID, LinkPlacement) -> Void) {
        _model = State(initialValue: AssignmentSheetModel(workspace: workspace, course: course, assignment: assignment))
        self.openFile = openFile
    }

    var body: some View {
        let files = model.files
        let scored = model.targetComponents
        let store = model.course.store
        SheetForm(
            title: model.sheetTitle, confirm: String(localized: .commonSave),
            disabled: model.title.isEmpty || model.invalid,
            carded: false, width: 560, deleteTitle: String(localized: .assignmentsDelete), onDelete: { model.delete { dismiss() } }
        ) {
            Block(String(localized: .assignmentsSheetAssignment)) {
                Card {
                    FormRow(label: String(localized: .assignmentsFieldTitle), detail: model.titleDetail) {
                        InlineField(String(localized: .assignmentsFieldTitleExample), text: $model.title)
                    }
                    FormRow(label: String(localized: .assignmentsFieldDue)) {
                        if model.hasDue {
                            DateChip(date: $model.due)
                            Button {
                                model.hasDue = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help(Text(.assignmentsClearDue))
                        } else {
                            Button(.assignmentsSetDue) { model.hasDue = true }.buttonStyle(.ghost)
                        }
                    }
                    FormRow(label: String(localized: .assignmentsFieldRepeat), detail: model.repeatDetail) {
                        Menu {
                            RepeatMenuItems(
                                selection: model.repeats, custom: model.customRepeat, pick: model.pickRepeat,
                                customize: model.customizeRepeat)
                        } label: {
                            ChipLabel(model.repeatLabel)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain).pointingHand()
                        .fixedSize()
                    }
                    if model.customRepeat {
                        RepeatRuleRows(rule: $model.customRule, dueWeekday: model.dueWeekday)
                    }
                    FormRow(label: String(localized: .assignmentsStatus), last: true) {
                        ChoiceMenu(
                            selection: $model.status, options: [AssignmentStatus.todo, .doing, .submitted, .graded].map { ($0, $0.label) })
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
                            TextField(
                                String(localized: .assignmentsScore),
                                text: Binding(get: { model.scores[c.id] ?? "" }, set: { model.scores[c.id] = $0 })
                            ).pill(width: 72)
                            Text("/").foregroundStyle(Theme.Palette.textTertiary)
                            TextField(
                                String(localized: .assignmentsMax),
                                text: Binding(get: { model.maxes[c.id] ?? "" }, set: { model.maxes[c.id] = $0 })
                            ).pill(width: 72)
                        }
                    }
                }
                .sensitive(scored.isEmpty ? nil : .block)
            }
            FormTextArea(label: String(localized: .assignmentsMemo), text: $model.memo)
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
                        .contextMenu {
                            if model.opens(m) { Button(.assignmentsOpen) { open(m) } }
                            if m.isFolder { EditorMenu(url: store.fileURL(m.path)) }
                        }
                    }
                }
                .fileDrop { model.importFiles($0) }
            }
        } onConfirm: {
            if model.apply() { dismiss() }
        }
        .confirming($model.pending)
        .confirmationDialog(
            String(localized: .assignmentsOpenUnsaved), isPresented: asking, titleVisibility: .visible, presenting: model.opening
        ) { m in
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
        switch model.open(m, windows: multipleWindows) {
        case .elsewhere(let url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        case .materials(let id): show(id)
        case .window(let id): openFile(id, .window)
        case .asks: break
        }
    }

    func show(_ id: UUID) {
        dismiss()
        openFile(id, .here)
    }
}
