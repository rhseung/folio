import FolioDomain
import SwiftUI

/// The end-of-class wrap-up as one plain form: every item as its control, in asking order, holding what the class has
/// or what is suggested for it. Announcements made in class can be added below, or skipped.
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
            ForEach(model.items, id: \.self) { item in
                Block(model.label(item)) { Card { row(item) } }
            }
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
        .environment(\.accent, model.accent)
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

    @ViewBuilder func row(_ item: WrapUpItem) -> some View {
        switch item {
        case .progress: progress
        case .units: units
        case .note: note
        case .attendance:
            CardRow(last: true) {
                attendance
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
        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            CardRow(last: i == rows.count - 1 && model.addable.isEmpty) {
                CheckCircle(on: row.included) { model.toggle(row.id) }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(model.name(row.id)).lineLimit(1).truncationMode(.middle)
                        .opacity(row.included ? 1 : Theme.Opacity.ended)
                    // The file's own action, under its name: the bar beside it is only for picking pages.
                    if model.sections(row.id).isEmpty {
                        Button { split(row.id) } label: { Label(.designPageRangeSplit, systemImage: "scissors") }
                            .buttonStyle(.pointing(.plain))
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(model.accent.ink)
                            .help(Text(.designPageRangeSplitHelp))
                    }
                }
                .frame(width: 136, alignment: .leading)
                // All the rest of the row: the tiles' names need every point the bar can get.
                PageRangeField(range: row.range, pages: model.pageCounts[row.id], taught: model.taught(row.id),
                               seen: model.seen(row.id), sections: model.sections(row.id)) { model.setRange(row.id, $0) }
                    .frame(maxWidth: .infinity)
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
        // No chips is no units, so no row for them: an empty row held only the picker.
        if !model.linkedUnits.isEmpty {
            CardRow {
                FlowLayout(spacing: Theme.Space.tight, centered: true) {
                    ForEach(model.linkedUnits) { unitChip($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        CardRow(last: true) {
            Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
            TextField(String(localized: .wrapUpUnitsNew), text: $model.newUnit).textFieldStyle(.plain).onSubmit { model.addUnit() }
            if !model.newUnit.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(.commonAdd) { model.addUnit() }.buttonStyle(.ghost)
            }
            // At the end of the one row that is always there, not after the chips: there it moved with every pick,
            // and the open popover, anchored to it, jumped away from the pointer.
            if !options.isEmpty {
                SearchPicker(options: options, isSelected: { model.units.contains($0) }, pick: { model.pick($0) }, multiple: true,
                             prompt: String(localized: .wrapUpUnitsSearch)) {
                    Label(.wrapUpUnitsAdd, systemImage: "plus").labelStyle(GhostLabelStyle()).foregroundStyle(.tint)
                }
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
