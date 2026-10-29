import FolioActions
import FolioDomain
import SwiftUI

struct ExamsView: View {
    @State private var model: ExamsModel
    @Environment(\.accent) private var accent
    let openNote: (UUID) -> Void

    static let dateColumn: CGFloat = 104

    init(workspace: Workspace, course: LoadedCourse, openNote: @escaping (UUID) -> Void) {
        _model = State(initialValue: ExamsModel(workspace: workspace, course: course))
        self.openNote = openNote
    }

    var body: some View {
        let now = Date.now
        let (coming, past) = model.exams(now: now)
        let states = model.reviewStates(now: now)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .examsTitle), subtitle: model.subtitle(coming: coming.count, past: past.count))
                Spacer()
                Button(.examsAdd) { model.add() }
                    .buttonStyle(.pointing(.borderedProminent))
            }
            if coming.isEmpty && past.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .examsEmpty)) } }
            }
            ForEach(coming) { exam in
                section(exam, states: states)
            }
            if !past.isEmpty {
                Block(String(localized: .examsPast), note: "\(past.count)") {
                    Card {
                        ForEach(Array(past.enumerated()), id: \.element.id) { i, exam in
                            CardRow(last: i == past.count - 1) { pastRow(exam) }
                                .contentShape(.rect)
                                .contextMenu { actions(exam) }
                                .fileDrop { model.drop($0, on: exam) }
                        }
                    }
                }
            }
        }
        .sheet(item: $model.editing) { ExamEditor(workspace: model.workspace, course: model.course, exam: $0) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.editExam, initial: true) { _, on in model.editing = on ? model.course.file.exams.first : nil }
        #endif
        .confirmationDialog(String(localized: .examsRemoveConfirm(model.removing?.title ?? "")),
                            isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }), presenting: model.removing) { exam in
            Button(.commonDelete, role: .destructive) { model.remove(exam) }
        } message: { _ in
            Text(.examsRemoveMessage)
        }
        .task(id: model.course.id) { model.load() }
    }

    func section(_ exam: Exam, states: [UUID: ReviewState]) -> some View {
        Block(title: exam.title, note: exam.kind.label) {
            if let start = exam.start { DdayChip(days: model.days(to: start)) }
        } content: {
            Card {
                CardRow {
                    when(exam, muted: false)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.m) {
                            fact("mappin.and.ellipse", exam.location, empty: String(localized: .examsNoLocation))
                            // Empty means not entered yet, not that nothing is allowed.
                            if !exam.allowed.isEmpty { fact("doc.text", exam.allowed, empty: "") }
                        }
                        if !exam.memo.isEmpty {
                            Text(exam.memo).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    summaryButton(exam)
                    menu(exam)
                }
                scope(exam, states: states)
                if let folder = model.folder(of: exam) {
                    CardRow(last: true) {
                        Label(folder, systemImage: "folder").foregroundStyle(Theme.Palette.textSecondary)
                        Text(model.folderDetail(folder))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                        Spacer(minLength: 0)
                    }
                }
            }
            .contextMenu { actions(exam) }
            .fileDrop { model.drop($0, on: exam) }
            ExamPlanCard(model: model, exam: exam)
        }
    }

    /// Date over weekday and time, in a fixed column as the session list has.
    func when(_ exam: Exam, muted: Bool) -> some View {
        let when = model.when(exam)
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(when.date).font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(muted || exam.start == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
            if let time = when.time {
                Text(time)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit().lineLimit(1)
            }
        }
        .frame(width: Self.dateColumn, alignment: .leading)
    }

    /// The scope's top units numbered, each marked with how its review stands.
    @ViewBuilder func scope(_ exam: Exam, states: [UUID: ReviewState]) -> some View {
        let scope = model.scope(exam, states: states)
        let today = model.today
        if scope.units.isEmpty {
            CardRow {
                Text(.examsScope).font(Theme.Typeface.bodyStrong)
                Text(model.scopeLine(exam, units: 0))
                    .foregroundStyle(exam.scopeText.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                Spacer(minLength: 0)
                if model.canPickScope { Button(.examsScopePick) { model.editing = exam }.buttonStyle(.ghost) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(.examsScope).font(Theme.Typeface.bodyStrong)
                    Text(model.scopeLine(exam, units: scope.units.count))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    Spacer(minLength: Theme.Space.m)
                    Text(.examsOnTrack(scope.onTrack, scope.units.count)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                        .help(Text(.examsOnTrackHelp))
                }
                Meter(value: Double(scope.onTrack) / Double(scope.units.count), height: 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.l, alignment: .leading)], alignment: .leading, spacing: 0) {
                    ForEach(Array(scope.tops.enumerated()), id: \.element.unit.id) { i, top in
                        HStack(spacing: Theme.Space.s) {
                            Text("\(i + 1)").font(Theme.Typeface.label).monospacedDigit().foregroundStyle(accent.ink)
                                .frame(width: 20, alignment: .trailing)
                            Text(top.unit.title).lineLimit(1)
                            if top.children > 0 { Text("+\(top.children)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit() }
                            Spacer(minLength: 0)
                            ReviewDot(state: states[top.unit.id], today: today)
                        }
                        .padding(.vertical, Theme.Space.tight)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .bottom) { Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l) }
        }
    }

    func pastRow(_ exam: Exam) -> some View {
        Group {
            when(exam, muted: true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(exam.title).font(Theme.Typeface.bodyStrong)
                Text(model.pastFacts(exam)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            summaryButton(exam)
            menu(exam)
        }
    }

    func summaryButton(_ exam: Exam) -> some View {
        Button(model.summaryTitle(exam)) { openSummary(exam) }
        .buttonStyle(.pointing(.bordered))
        .help(model.summaryHelp(exam))
    }

    func openSummary(_ exam: Exam) {
        if let id = model.openSummary(exam) { openNote(id) }
    }

    /// The ⋯ menu and the right-click menu, so both offer the same things.
    @ViewBuilder func actions(_ exam: Exam) -> some View {
        Button(model.summaryTitle(exam)) { openSummary(exam) }
        Button(.commonEditEllipsis) { model.editing = exam }
        Divider()
        Button(.commonDeleteEllipsis, role: .destructive) { model.removing = exam }
    }

    func menu(_ exam: Exam) -> some View {
        Menu {
            actions(exam)
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless).pointingHand()
        .fixedSize()
        .help(Text(.examsMenuHelp))
    }

    func fact(_ symbol: String, _ text: String, empty: String) -> some View {
        Label(text.isEmpty ? empty : text, systemImage: symbol)
            .font(Theme.Typeface.caption).lineLimit(1)
            .foregroundStyle(text.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
    }
}

/// The new item's day, title and unit are typed per card, so they stay with the card rather than the page's model.
struct ExamPlanCard: View {
    let model: ExamsModel
    let exam: Exam
    @State private var day = Date.now
    @State private var title = ""
    @State private var unit: UUID?

    var body: some View {
        let items = model.plan(exam)
        let today = model.today
        Card {
            CardRow {
                Text(.examsPlan).font(Theme.Typeface.bodyStrong)
                Text(model.planLine(items))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let on = model.done.contains(item.id)
                CardRow {
                    CheckCircle(on: on) { model.toggle(item.id) }.help(Text(on ? .examsPlanUndo : .examsPlanCheck))
                    Text(model.dayLabel(items, at: i))
                        .font(Theme.Typeface.caption.weight(item.day == today ? .semibold : .regular)).monospacedDigit()
                        .foregroundStyle(on ? Theme.Palette.textTertiary : item.day < today ? Theme.Palette.danger
                                         : item.day == today ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .frame(width: ExamsView.dateColumn, alignment: .leading)
                    Text(item.title).lineLimit(1)
                        .strikethrough(on, color: Theme.Palette.textTertiary)
                        .foregroundStyle(on ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let target = model.targetTitle(item) {
                        Text(target).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { model.removePlanItem(item.id, of: exam) } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.ghost)
                    .help(Text(.examsPlanRemove))
                }
                .contentShape(.rect)
                .contextMenu {
                    Button(on ? .examsPlanUndo : .examsPlanCheck) { model.toggle(item.id) }
                    Divider()
                    Button(.examsPlanRemove, role: .destructive) { model.removePlanItem(item.id, of: exam) }
                }
            }
            CardRow(last: true) {
                DateChip(date: $day, showsTime: false)
                TextField(String(localized: .examsPlanPrompt), text: $title).textFieldStyle(.plain).onSubmit(add)
                SearchSelect(selection: $unit, options: model.targets(exam))
                Button(.commonAdd, action: add).buttonStyle(.pointing(.bordered)).disabled(!model.canAdd(item))
            }
        }
        .onAppear { day = model.firstPlanDay }
    }

    var item: ExamPlanAdd { model.planItem(exam, title: title, day: day, unit: unit) }

    func add() {
        guard model.add(item) else { return }
        title = ""
    }
}

struct ExamEditor: View {
    @State private var model: ExamEditorModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, course: LoadedCourse, exam: Exam) {
        _model = State(initialValue: ExamEditorModel(workspace: workspace, course: course, exam: exam))
    }

    var body: some View {
        let units = model.units
        let course = model.course
        SheetForm(title: model.title, confirm: model.confirm, disabled: model.disabled, note: model.note, carded: false, width: 560) {
            Block(String(localized: .examsEditorExam)) {
                Card {
                    FormRow(label: String(localized: .examsEditorKind)) {
                        ChoiceMenu(selection: $model.draft.kind, options: [ExamKind.midterm, .final, .quiz, .other].map { ($0, $0.label) })
                    }
                    FormRow(label: String(localized: .examsEditorName), last: course.file.components.isEmpty) { InlineField(model.namePrompt, text: $model.draft.title) }
                    if !course.file.components.isEmpty {
                        FormRow(label: String(localized: .examsEditorComponent), last: true) {
                            ChoiceMenu(selection: $model.draft.componentId, options: model.components)
                        }
                    }
                }
            }
            Block(String(localized: .examsEditorWhenWhere)) {
                Card {
                    FormRow(label: String(localized: .examsEditorWhen), detail: model.endsBeforeStart ? String(localized: .examsEditorEndsBeforeStart) : nil) {
                        if model.draft.start == nil {
                            Button(.examsEditorSetDate) { model.setDefaultStart() }
                                .buttonStyle(.ghost)
                        } else {
                            DateChip(date: Binding(get: { model.draft.start ?? .now }, set: model.setStart))
                            Text("–").foregroundStyle(Theme.Palette.textTertiary)
                            if let end = model.endMinute {
                                TimeMenu(minute: Binding(get: { end }, set: model.setEnd))
                                Button { model.setEnd(nil) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help(Text(.examsEditorClearEnd))
                            } else {
                                Button(.examsEditorAddEnd) { model.addEnd() }.buttonStyle(.ghost)
                            }
                        }
                    }
                    FormRow(label: String(localized: .examsEditorLocation)) { TextField(String(localized: .examsEditorLocationExample), text: $model.draft.location).pill(width: 140) }
                    FormRow(label: String(localized: .examsEditorAllowed), last: true) { InlineField(String(localized: .examsEditorAllowedExample), text: $model.draft.allowed) }
                }
            }
            Block(String(localized: .examsScope)) {
                Card {
                    FormRow(label: String(localized: .examsEditorUnits)) {
                        SearchMultiSelect(selection: $model.draft.scopeUnitIds, options: units.map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) },
                                          placeholder: String(localized: units.isEmpty ? .examsEditorNoUnits : .examsEditorPick),
                                          subtree: { UnitTree.subtree(of: $0, in: course.file.units) })
                            .disabled(units.isEmpty)
                    }
                    FormRow(label: String(localized: .examsEditorScopeText), last: true) {
                        InlineField(String(localized: .examsEditorScopeTextExample), text: $model.draft.scopeText)
                    }
                }
            }
            FormTextArea(label: String(localized: .examsEditorMemo), text: $model.draft.memo, height: 56)
        } onConfirm: {
            if model.apply() { dismiss() }
        }
    }
}

struct ExamPlanTodayBlock: View {
    @Environment(Workspace.self) private var workspace
    let courses: [LoadedCourse]
    @State private var done: Set<UUID> = []

    var body: some View {
        let today = workspace.today
        let items = ExamPlan.items(on: today, courses: courses.map(\.file))
        if !items.isEmpty {
            Block(String(localized: .examsPlan), note: String(localized: .examsPlanDone(items.filter { done.contains($0.item.id) }.count, items.count))) {
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { i, entry in
                        let accent = workspace.accent(entry.courseId)
                        CardRow(last: i == items.count - 1) {
                            CheckCircle(on: done.contains(entry.item.id)) { toggle(entry) }
                            .help(Text(done.contains(entry.item.id) ? .examsPlanUndo : .examsPlanCheck))
                            .environment(\.accent, accent)
                            CourseDot(color: accent.color)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(entry.item.title).font(Theme.Typeface.bodyStrong).strikethrough(done.contains(entry.item.id))
                                Text("\(workspace.course(entry.courseId)?.title ?? "") · \(entry.exam.title)")
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                        .contextMenu { Button(done.contains(entry.item.id) ? .examsPlanUndo : .examsPlanCheck) { toggle(entry) } }
                    }
                }
            }
            .task(id: courses.map(\.id)) { done = workspace.donePlanItems(in: courses.map(\.id)) }
        }
    }

    func toggle(_ entry: ExamPlan.DayItem) {
        let new = !done.contains(entry.item.id)
        workspace.setPlanItem(entry.item.id, done: new, course: entry.courseId)
        if new { done.insert(entry.item.id) } else { done.remove(entry.item.id) }
    }
}

private struct ReviewDot: View {
    let state: ReviewState?
    let today: LocalDate

    var body: some View {
        let (color, label): (Color?, String) = {
            guard let state else { return (nil, String(localized: .examsReviewNotYet)) }
            if state.settled && state.due == nil { return (Theme.Palette.success, String(localized: .examsReviewSettled)) }
            guard let due = state.due else { return (Theme.Palette.textTertiary, String(localized: .examsReviewOngoing)) }
            let late = due.days(until: today)
            let note = state.writeNoteFirst ? String(localized: .examsReviewNoNote) + " · " : ""
            return late > 0 ? (Theme.Palette.danger, note + String(localized: .examsReviewLate(late)))
                : late == 0 ? (Theme.Palette.warning, note + String(localized: .examsReviewToday))
                : (Theme.Palette.textTertiary, String(localized: .examsReviewNext(due.shortLabel)))
        }()
        Group {
            if let color { Circle().fill(color) } else { Circle().strokeBorder(Theme.Palette.line, lineWidth: 1.5) }
        }
        .frame(width: 8, height: 8)
        .help(label)
        .accessibilityLabel(label)
    }
}
