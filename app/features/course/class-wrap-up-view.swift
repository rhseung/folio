import FolioDomain
import SwiftUI

/// The end-of-class wrap-up on one sheet: what the class has nothing for opens for input, in asking order, and what it
/// has folds into one line each under "채운 것" to confirm. Attendance folds as its choice itself rather than a line with
/// 바꾸기, so a recorded class marked present is one press from late. Announcements made in class can be added below, or skipped.
struct ClassWrapUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @State private var model: ClassWrapUpModel
    @State private var splitting: UUID?
    var step: String?
    /// Set in a run through several classes, which moves on to the next instead of closing.
    var saved: (() -> Void)?

    init(workspace: Workspace, course: UUID, session: UUID, viewed: [SessionMaterial] = [], recorded: Bool = false,
         step: String? = nil, saved: (() -> Void)? = nil) {
        _model = State(initialValue: ClassWrapUpModel(workspace: workspace, course: course, session: session, viewed: viewed, recorded: recorded))
        self.step = step
        self.saved = saved
    }

    var body: some View {
        SheetForm(title: model.title, confirm: String(localized: .commonSave), disabled: model.refusal != nil, note: model.note,
                  carded: false, width: 640, mark: CourseMark(model.workspace, model.courseId), cancel: String(localized: .wrapUpLater),
                  step: step) {
            ForEach(model.openItems, id: \.self) { item in
                Block(model.label(item)) { Card { open(item) } }
            }
            let folded = model.folded
            if !folded.isEmpty {
                Block(String(localized: .wrapUpFilled), note: String(localized: .wrapUpFilledNote)) {
                    Card {
                        ForEach(Array(folded.enumerated()), id: \.element) { i, item in
                            CardRow(last: i == folded.count - 1) {
                                Text(model.label(item)).foregroundStyle(Theme.Palette.textSecondary).frame(width: 64, alignment: .leading)
                                if item == .attendance && model.takesAttendance {
                                    attendance
                                    Spacer(minLength: 0)
                                } else {
                                    Text(model.summary(item)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: Theme.Space.s)
                                    Button(.wrapUpChange) { withAnimation(.snappy) { model.reopen(item) } }.buttonStyle(.ghost)
                                }
                            }
                        }
                    }
                }
            }
            announcements
        } onConfirm: {
            guard model.wrapUp() else { return }
            if let saved { saved() } else { dismiss() }
        }
        .task { await model.load() }
        .confirmationDialog(String(localized: .assignmentsOpenUnsaved), isPresented: Binding(get: { splitting != nil }, set: { if !$0 { splitting = nil } }),
                            titleVisibility: .visible, presenting: splitting) { id in
            Button(.assignmentsOpenSave) {
                guard model.wrapUp() else { return }
                leave(for: id)
            }
            Button(.assignmentsOpenDiscard, role: .destructive) { leave(for: id) }
            Button(.commonCancel, role: .cancel) { splitting = nil }
        } message: { _ in
            Text(.sessionsProgressSplitUnsaved)
        }
        .courseAccent(model.accent)
        .sheet(item: $model.addingExam, onDismiss: nil) { exam in
            if let course = model.course {
                ExamEditor(workspace: model.workspace, course: course, exam: exam)
                    .onDisappear { model.examClosed(exam) }
            }
        }
    }

    /// To the file's split screen (#321). With nothing changed here the sheet closes and the file opens in this tab;
    /// with changes the sheet stays and the file opens in a new window, or where there is no other window, it asks.
    private func split(_ id: UUID) {
        if !model.changed { return leave(for: id) }
        if multipleWindows {
            model.workspace.splitAsk = id
            openLink(AppLink(.material, id), in: .window, course: model.courseId)
        } else {
            splitting = id
        }
    }

    private func leave(for id: UUID) {
        model.workspace.splitAsk = id
        dismiss()
        openLink(AppLink(.material, id), course: model.courseId)
    }

    @ViewBuilder func open(_ item: WrapUpItem) -> some View {
        switch item {
        case .progress: progress
        case .units: units
        case .note: note
        case .attendance:
            CardRow(last: true) {
                if model.takesAttendance { attendance } else { EmptyLine(String(localized: .wrapUpAttendanceNone)) }
                Spacer(minLength: 0)
            }
        }
    }

    var attendance: some View {
        Segmented(selection: $model.attendance, options: AttendanceState.steps.map { ($0.value, $0.label) })
    }

    // MARK: Progress

    @ViewBuilder var progress: some View {
        let rows = model.rows
        if rows.isEmpty {
            CardRow(last: model.addable.isEmpty) { EmptyLine(String(localized: .sessionsProgressEmpty)) }
        }
        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            CardRow(last: i == rows.count - 1 && model.addable.isEmpty) {
                CheckCircle(on: row.included) { model.toggle(row.id) }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(model.name(row.id)).lineLimit(1).truncationMode(.middle)
                    let detail = model.detail(row.id)
                    if !detail.isEmpty {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 176, alignment: .leading)
                .opacity(row.included ? 1 : Theme.Opacity.ended)
                Spacer(minLength: Theme.Space.s)
                PageRangeField(range: row.range, pages: model.pageCounts[row.id], taught: model.taught(row.id),
                               seen: model.seen(row.id), resume: model.resume(row.id), sections: model.sections(row.id),
                               reads: model.reads(row.id), split: { split(row.id) }) { model.setRange(row.id, $0) }
                    .opacity(row.included ? 1 : Theme.Opacity.ended)
            }
        }
        if !model.addable.isEmpty {
            CardRow(last: true) {
                Menu {
                    ForEach(model.addable) { m in
                        Button((m.path as NSString).lastPathComponent) { model.add(m.id) }
                    }
                } label: {
                    Label(.sessionsProgressAddFile, systemImage: "plus")
                }
                .menuStyle(.button).buttonStyle(.ghost).fixedSize()
                Spacer()
            }
        }
    }

    // MARK: Units

    /// The class's units as chips that wrap, so a long title is read whole, and "+ 단원" for the course's whole outline.
    /// Nothing is put forward: which unit the class covered is the user's call (#147).
    @ViewBuilder var units: some View {
        let options = model.unitOptions
        if !options.isEmpty {
            CardRow {
                let linked = model.linkedUnits
                Group {
                    if linked.isEmpty {
                        EmptyLine(String(localized: .wrapUpUnitsNone))
                    } else {
                        FlowLayout(spacing: Theme.Space.tight, centered: true) {
                            ForEach(linked) { unitChip($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Outside the chips, at the row's end: placed after them it moved with every pick, and the open
                // popover, anchored to it, jumped away from the pointer.
                SearchPicker(options: options, isSelected: { model.units.contains($0) }, pick: { model.pick($0) }, multiple: true,
                             prompt: String(localized: .wrapUpUnitsSearch)) {
                    Label(.wrapUpUnitsAdd, systemImage: "plus").labelStyle(GhostLabelStyle()).foregroundStyle(.tint)
                }
            }
        }
        CardRow(last: true) {
            Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
            TextField(String(localized: .wrapUpUnitsNew), text: $model.newUnit).textFieldStyle(.plain).onSubmit { model.addUnit() }
            if !model.newUnit.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(.commonAdd) { model.addUnit() }.buttonStyle(.ghost)
            }
        }
    }

    private func unitChip(_ unit: FolioDomain.Unit) -> some View {
        HStack(spacing: Theme.Space.xs) {
            // Wraps within the row instead of truncating: unit titles run long ("Walk, Trail, Path, Cycle, Girth").
            Text(unit.title).fixedSize(horizontal: false, vertical: true)
            Button { model.removeUnit(unit.id) } label: {
                Image(systemName: "xmark").font(Theme.Glyph.tiny).foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(.commonRemove))
            .accessibilityLabel(Text(.wrapUpUnitsRemove(unit.title)))
        }
        .chip()
        .contextMenu { Button(.commonRemove, role: .destructive) { model.removeUnit(unit.id) } }
    }

    // MARK: Note

    var note: some View {
        CardRow(last: true) {
            if let linked = model.linkedNote {
                noteMenu(linked)
            } else {
                CheckCircle(on: model.makesNote) { model.makesNote.toggle() }
                Text(.wrapUpNoteMake).foregroundStyle(model.makesNote ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .onTapGesture { model.makesNote.toggle() }
                Spacer(minLength: Theme.Space.s)
                let notes = model.noteChoices
                if !notes.isEmpty {
                    Menu {
                        ForEach(notes) { n in Button(model.noteName(n)) { model.linkNote(n.id) } }
                    } label: {
                        Text(.wrapUpNoteLink)
                    }
                    .menuStyle(.button).buttonStyle(.ghost).fixedSize()
                }
            }
        }
    }

    /// The linked note is the menu's label, so the whole row opens it, by click or by keyboard as any menu button.
    private func noteMenu(_ linked: NoteEntry) -> some View {
        Menu {
            let notes = model.noteChoices
            Menu(String(localized: .wrapUpNoteOther)) {
                ForEach(notes) { n in Button(model.noteName(n)) { model.linkNote(n.id) } }
                if notes.isEmpty { Text(.wrapUpNoteNone) }
            }
            Button(.wrapUpNoteNew, systemImage: "plus") { model.makeNewNote() }
            Divider()
            Button(.wrapUpNoteUnlink, systemImage: "link.badge.minus", role: .destructive) { model.unlinkNote() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "doc.text").foregroundStyle(Theme.Palette.textTertiary)
                Text(model.noteName(linked)).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.Palette.text)
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.pointing(.plain))
        .menuIndicator(.hidden)
    }

    // MARK: Announcements

    var announcements: some View {
        Block(String(localized: .wrapUpAnnouncements), note: String(localized: .wrapUpAnnouncementsNote)) {
            Card {
                ForEach(model.announced, id: \.self) { line in
                    CardRow {
                        Image(systemName: "checkmark").foregroundStyle(Theme.Palette.success)
                        Text(line).lineLimit(1)
                    }
                }
                CardRow(last: true) {
                    Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .wrapUpAssignmentPrompt), text: $model.assignmentText).textFieldStyle(.plain)
                        .onSubmit { model.addAssignment() }
                    if let parsed = model.parsedAssignment, !parsed.title.isEmpty {
                        Button(.wrapUpAssignmentAdd) { model.addAssignment() }.buttonStyle(.ghost)
                    }
                    Button { model.addExam() } label: { Label(.wrapUpExamAdd, systemImage: "plus") }.buttonStyle(.ghost)
                }
            }
        }
    }
}

/// Shows the wrap-up a stopped recording asks for, in the window it was stopped from. Every window watches the same
/// ask; the first that takes it clears it, so two windows don't both ask.
struct ClassWrapUpPrompt: ViewModifier {
    let workspace: Workspace
    @State private var shown: ClassWrapUpAsk?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: workspace.wrapUpAsk) { _, ask in
                guard let ask, workspace.wrapUpAsk == ask else { return }
                #if os(macOS)
                // The stop button was in the key window.
                guard active else { return }
                workspace.wrapUpAsk = nil
                shown = ask
                #else
                workspace.wrapUpAsk = nil
                // The recording card's popover is still going away; a sheet asked for meanwhile is dropped.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    shown = ask
                }
                #endif
            }
            .sheet(item: $shown) { ask in
                ClassWrapUpSheet(workspace: workspace, course: ask.course, session: ask.session, viewed: ask.viewed, recorded: true)
            }
    }
}

extension View {
    func classWrapUpPrompt(_ workspace: Workspace) -> some View { modifier(ClassWrapUpPrompt(workspace: workspace)) }
}
