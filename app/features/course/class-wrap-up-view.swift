import FolioDomain
import SwiftUI

/// The end-of-class wrap-up on one sheet: what the class has nothing for opens for input, in asking order, and what it
/// has folds into one line each under "채운 것" to confirm. Announcements made in class can be added below, or skipped.
struct ClassWrapUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ClassWrapUpModel

    init(workspace: Workspace, course: UUID, session: UUID, viewed: [SessionMaterial] = [], recorded: Bool = false) {
        _model = State(initialValue: ClassWrapUpModel(workspace: workspace, course: course, session: session, viewed: viewed, recorded: recorded))
    }

    var body: some View {
        SheetForm(title: model.title, confirm: String(localized: .commonSave), disabled: model.refusal != nil, note: model.note,
                  carded: false, width: 640, mark: CourseMark(model.workspace, model.courseId), cancel: String(localized: .wrapUpLater)) {
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
                                Text(model.summary(item)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: Theme.Space.s)
                                Button(.wrapUpChange) { withAnimation(.snappy) { model.reopen(item) } }.buttonStyle(.ghost)
                            }
                        }
                    }
                }
            }
            announcements
        } onConfirm: {
            model.wrapUp()
            dismiss()
        }
        .task { await model.load() }
        .environment(\.accent, model.accent)
        .sheet(item: $model.addingExam, onDismiss: nil) { exam in
            if let course = model.course {
                ExamEditor(workspace: model.workspace, course: course, exam: exam)
                    .onDisappear { model.examClosed(exam) }
            }
        }
    }

    @ViewBuilder func open(_ item: WrapUpItem) -> some View {
        switch item {
        case .progress: progress
        case .units: units
        case .topic:
            CardRow(last: true) {
                TextField(String(localized: .wrapUpTopicPrompt), text: $model.topic).textFieldStyle(.plain)
            }
        case .note: note
        case .attendance:
            CardRow(last: true) {
                if model.takesAttendance {
                    Segmented(selection: $model.attendance, options: AttendanceState.steps.map { ($0.value, $0.label) })
                } else {
                    EmptyLine(String(localized: .wrapUpAttendanceNone))
                }
                Spacer(minLength: 0)
            }
        }
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
                               seen: model.seen(row.id), resume: model.resume(row.id)) { model.setRange(row.id, $0) }
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
        if !options.isEmpty {
            CardRow {
                SearchMultiSelect(selection: $model.units, options: options, placeholder: String(localized: .wrapUpUnitsPick),
                                  summary: model.units.isEmpty ? nil : model.unitTitles(model.units))
                // The last class's units, a press away but not chosen: whether a unit is done is the user's call.
                ForEach(model.recentUnits) { u in
                    Button { model.pick(u.id) } label: { Label(u.title, systemImage: "plus") }
                        .buttonStyle(.ghost)
                        .help(Text(.wrapUpUnitsRecentHelp))
                }
                Spacer(minLength: 0)
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

    // MARK: Note

    var note: some View {
        CardRow(last: true) {
            if model.hasNote {
                Text(model.summary(.note)).lineLimit(1)
                Spacer()
            } else {
                CheckCircle(on: model.makesNote) { model.makesNote.toggle() }
                Text(.wrapUpNoteMake).foregroundStyle(model.makesNote ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .onTapGesture { model.makesNote.toggle() }
                Spacer(minLength: Theme.Space.s)
                let notes = model.unlinkedNotes
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
