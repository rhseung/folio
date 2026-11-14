import FolioDomain
import SwiftUI

struct SessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @State private var model: SessionSheetModel
    @State private var splitting: UUID?
    @State private var height: CGFloat = 0
    let focus: SessionSection?
    let asked: Bool
    var step: String?
    var saved: (() -> Void)?

    static let maxHeight: CGFloat = 520

    init(workspace: Workspace, request: SessionSheetRequest, step: String? = nil, saved: (() -> Void)? = nil) {
        self.init(
            model: SessionSheetModel(workspace: workspace, request: request), focus: request.focus, asked: request.asked, step: step,
            saved: saved)
    }

    init(model: SessionSheetModel, focus: SessionSection? = nil, asked: Bool = false, step: String? = nil, saved: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.focus = focus
        self.asked = asked
        self.step = step
        self.saved = saved
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: model.confirm, disabled: model.disabled, note: model.note,
            carded: false, width: 640, mark: CourseMark(model.workspace, model.courseId),
            cancel: asked ? String(localized: .wrapUpLater) : nil, step: step
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        ForEach(model.sections, id: \.self) { section in
                            Block(model.label(section)) { Card { rows(section) } }.id(section)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .overflowFade(.vertical)
                .frame(height: min(height, Self.maxHeight))
                .task(id: height > 0) {
                    guard height > 0, let focus else { return }
                    proxy.scrollTo(focus, anchor: .top)
                }
            }
        } onConfirm: {
            guard model.submit() else { return }
            if let saved { saved() } else { dismiss() }
        }
        .task { await model.load() }
        .confirmationDialog(
            String(localized: .assignmentsOpenUnsaved),
            isPresented: Binding(get: { splitting != nil }, set: { if !$0 { splitting = nil } }),
            titleVisibility: .visible, presenting: splitting
        ) { id in
            Button(.assignmentsOpenSave) {
                guard model.submit() else { return }
                leave(for: id)
            }
            Button(.assignmentsOpenDiscard, role: .destructive) { leave(for: id) }
            Button(.commonCancel, role: .cancel) { splitting = nil }
        } message: { _ in
            Text(.sessionsProgressSplitUnsaved)
        }
        .courseAccent(model.accent)
    }

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

    @ViewBuilder func rows(_ section: SessionSection) -> some View {
        switch section {
        case .progress: progress
        case .units: units
        case .notes: notes
        case .attendance:
            CardRow(last: true) {
                Segmented(selection: $model.attendance, options: AttendanceState.steps.map { ($0.value, $0.label) })
                Spacer(minLength: 0)
            }
        case .info: info
        }
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
                    if model.zones(row.id).isEmpty {
                        Button {
                            split(row.id)
                        } label: {
                            Label(.designPageRangeSplit, systemImage: "scissors")
                        }
                        .buttonStyle(.pointing(.plain))
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(model.accent.ink)
                        .help(Text(.designPageRangeSplitHelp))
                    }
                }
                .frame(width: 136, alignment: .leading)
                PageRangeField(
                    range: row.range, pages: model.pageCounts[row.id], taught: model.taught(row.id),
                    seen: model.seen(row.id), sections: model.zones(row.id)
                ) { model.setRange(row.id, $0) }
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

    @ViewBuilder var units: some View {
        let options = model.unitOptions
        if !model.linkedUnits.isEmpty {
            CardRow {
                FlowLayout(spacing: Theme.Space.tight, centered: true) {
                    ForEach(model.linkedUnits) { unitChip($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        CardRow(last: true) {
            SearchPicker(
                options: options, isSelected: { model.units.contains($0) }, pick: { model.pick($0) }, multiple: true,
                prompt: String(localized: .wrapUpUnitsSearch), flexible: true, create: { model.makeUnit($0) },
                createTitle: { String(localized: .sessionSheetUnitsNew($0)) }
            ) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "plus")
                    Text(.sessionSheetUnitsAdd)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.tint)
                .contentShape(.rect)
            }
        }
    }

    private func unitChip(_ unit: FolioDomain.Unit) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(unit.title).fixedSize(horizontal: false, vertical: true)
            Button {
                model.removeUnit(unit.id)
            } label: {
                Image(systemName: "xmark").font(Theme.Glyph.tiny).foregroundStyle(Theme.Palette.textTertiary)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(.commonRemove))
            .accessibilityLabel(Text(.wrapUpUnitsRemove(unit.title)))
        }
        .chip()
        .contextMenu { Button(.commonRemove, role: .destructive) { model.removeUnit(unit.id) } }
    }

    // MARK: Notes

    @ViewBuilder var notes: some View {
        CardRow(last: !model.showsReview) {
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
        if model.showsReview, let review = model.review {
            FormRow(label: String(localized: .sessionSheetReview), last: true) {
                Segmented(
                    selection: Binding(get: { model.review ?? review }, set: { model.review = $0 }),
                    options: review.choices.map { ($0, model.reviewLabel($0)) })
            }
        }
    }

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

    // MARK: When and how

    @ViewBuilder var info: some View {
        FormRow(label: String(localized: .sessionsDate)) { DateChip(date: Binding(get: { model.start }, set: { model.setStart($0) })) }
        FormRow(label: String(localized: .sessionsEnd)) { TimeMenu(minute: Binding(get: { model.endMinute }, set: { model.setEnd($0) })) }
        FormRow(label: String(localized: .sessionsKind)) {
            Segmented(selection: Binding(get: { model.kind }, set: { model.setKind($0) }), options: model.kindOptions)
        }
        FormRow(label: String(localized: .sessionsLink), detail: String(localized: .sessionsLinkDetail), last: true) {
            InlineField(String(localized: .sessionsLinkPrompt), text: $model.link)
        }
    }
}
