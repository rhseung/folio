import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitsView: View {
    @State private var model: UnitsModel
    let course: LoadedCourse

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: UnitsModel(workspace: workspace, courseId: course.id))
        self.course = course
    }

    var body: some View {
        Group {
            if let id = model.openUnit, let unit = course.file.units.first(where: { $0.id == id }) {
                UnitDetail(model: model, course: course, unit: unit, delete: { model.removing = unit })
            } else {
                list
            }
        }
        .task(id: course.file.units.map(\.id)) { model.loadQuiz(course) }
        .confirmationDialog(model.removalTitle, isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } })) {
            Button(.commonDelete, role: .destructive) {
                if let unit = model.removing { model.remove(unit) }
            }
        } message: {
            Text(.unitsDeleteMessage)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.unitStep, initial: true) { _, step in
            if step != nil { model.openUnit = UnitTree.outline(course.file.units).first?.unit.id }
        }
        #endif
    }

    /// A chapter (a top-level unit with units under it) heads its own block; top-level units without children
    /// share a plain card, so a flat outline still reads as one list.
    struct Chapter: Identifiable {
        var root: FolioDomain.Unit?
        var rows: [(unit: FolioDomain.Unit, depth: Int)] = []
        var id: UUID? { root?.id ?? rows.first?.unit.id }
    }

    static func groups(_ outline: [(unit: FolioDomain.Unit, depth: Int)]) -> [Chapter] {
        var groups: [Chapter] = []
        for (i, row) in outline.enumerated() {
            let hasChildren = i + 1 < outline.count && outline[i + 1].depth > row.depth
            if row.depth == 0 && hasChildren {
                groups.append(Chapter(root: row.unit))
            } else if row.depth == 0 {
                if groups.last.map({ $0.root == nil }) != true { groups.append(Chapter()) }
                groups[groups.count - 1].rows.append(row)
            } else {
                groups[groups.count - 1].rows.append((row.unit, row.depth - 1))
            }
        }
        return groups
    }

    var list: some View {
        let file = course.file
        let states = model.states()
        let today = model.today
        let unlinked = file.sessionsNeedingUnits(at: model.workspace.now)
        return Page {
            PageHeader(title: String(localized: .unitsTitle), subtitle: model.subtitle(file, states: states))
            if !unlinked.isEmpty { unlinkedCard(unlinked) }
            ForEach(Self.groups(UnitTree.outline(file.units))) { group in
                if let root = group.root {
                    let exams = model.exams(of: root, in: file)
                    Block(title: root.title, note: model.sessionsLine(root, in: file), trailing: {
                        HStack(spacing: Theme.Space.s) {
                            ForEach(exams) { Chip($0.title) }
                            ReviewBadge(state: states[root.id], today: today)
                            Button { model.openUnit = root.id } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.ghost).tint(Theme.Palette.textTertiary)
                                .help(Text(.unitsOpen))
                        }
                    }) {
                        Card { rows(group.rows, states: states, today: today, inheritedExams: Set(exams.map(\.id))) }
                    }
                    .contextMenu { menu(root) }
                } else {
                    Card { rows(group.rows, states: states, today: today, inheritedExams: []) }
                }
            }
            Card {
                CardRow(last: true) {
                    Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .unitsNewName), text: $model.newTitle).textFieldStyle(.plain).onSubmit(model.add)
                    Button(.commonAdd, action: model.add).buttonStyle(.pointing(.borderedProminent)).disabled(!model.canAdd)
                }
            }
            if file.units.isEmpty {
                EmptyLine(String(localized: .unitsEmpty))
                    .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    /// Exam chips only where they differ from the chapter's, so a chapter all in the midterm says it once.
    func rows(_ rows: [(unit: FolioDomain.Unit, depth: Int)], states: [UUID: ReviewState], today: LocalDate, inheritedExams: Set<UUID>) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.unit.id) { i, row in
            let unit = row.unit
            let exams = model.exams(of: unit, in: course.file)
            CardRow(last: i == rows.count - 1) {
                Button { model.openUnit = unit.id } label: {
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(unit.title).font(Theme.Typeface.body)
                            Text(model.detail(unit, state: states[unit.id], in: course.file)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.m)
                        if Set(exams.map(\.id)) != inheritedExams { ForEach(exams) { Chip($0.title) } }
                        ReviewBadge(state: states[unit.id], today: today)
                    }
                    .padding(.leading, CGFloat(row.depth) * Theme.Space.xl)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
            }
            .contextMenu { menu(unit) }
        }
    }

    @ViewBuilder func menu(_ unit: FolioDomain.Unit) -> some View {
        Button(.commonOpen) { model.openUnit = unit.id }
        Button(.unitsMoveUp) { model.move(unit, by: -1) }
        Button(.unitsMoveDown) { model.move(unit, by: 1) }
        Divider()
        Button(.commonDeleteEllipsis, role: .destructive) { model.removing = unit }
    }

    /// Held classes no unit covers, newest first: linking one here starts its unit's review from that class.
    func unlinkedCard(_ sessions: [Session]) -> some View {
        let shown = sessions.prefix(6)
        return NoticeCard(title: String(localized: .unitsUnlinkedTitle(sessions.count)),
                          detail: String(localized: .unitsUnlinkedDetail),
                          systemImage: "link.badge.plus", trailing: { EmptyView() }) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && sessions.count <= shown.count) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(course.file.title(of: s)).lineLimit(1)
                        Text(s.date.formatted(.dateTime.month().day().weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.m)
                    SessionUnitsPicker(course: course, session: s)
                }
            }
            if sessions.count > shown.count {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(sessions.count - shown.count))) }
            }
        }
    }
}

struct ReviewBadge: View {
    let state: ReviewState?
    let today: LocalDate

    var body: some View {
        if let state {
            if state.settled && state.due == nil {
                Chip(String(localized: .unitsReviewDone), tone: .success)
            } else if let due = state.due {
                let late = due.days(until: today)
                if state.writeNoteFirst && late >= 0 {
                    Chip(String(localized: late > 0 ? .unitsBadgeNoteLate(late) : .unitsBadgeNote), tone: .warning)
                } else if late > 0 {
                    Chip(String(localized: .unitsDaysLate(late)), tone: .danger)
                } else if late == 0 {
                    Chip(String(localized: .unitsToday), tone: .accent)
                } else {
                    Chip(due.shortLabel)
                }
            }
        } else {
            Chip(String(localized: .unitsBadgeNotStarted))
        }
    }
}

extension LocalDate {
    var shortLabel: String {
        date(in: .current)?.formatted(.dateTime.month().day().weekday()) ?? description
    }
}

/// Renaming, moving and deleting the unit come last, since they are rare.
struct UnitDetail: View {
    @Environment(\.accent) private var accent
    @Environment(\.searchTarget) private var searchTarget
    @Bindable var model: UnitsModel
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    let delete: () -> Void
    @State private var reviewing = false

    var body: some View {
        let file = course.file
        let now = model.workspace.now
        let today = model.studyDay(now)
        let state = model.states(now: now)[unit.id]
        let sessions = model.sessions(of: unit, in: file)
        let history = model.history(unit)
        let otherNotes = model.otherNotes(unit, in: file)
        let materials = model.materials(unit, in: file)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: unit.title, subtitle: model.parentPath(unit, in: file)) { ReviewBadge(state: state, today: today) }
                Spacer()
                Button { reviewing = true } label: { Label(.unitsStartReview, systemImage: "play.fill") }
                    .buttonStyle(.pointing(.borderedProminent))
                    .controlSize(.large)
            }

            StatStrip(items: model.stats(unit, state: state, reviews: history.count))

            Block(title: String(localized: .unitsSessionsBlock), note: sessions.isEmpty ? nil : String(localized: .unitsTimes(sessions.count))) {
                ToggleMenu(title: String(localized: .unitsLinkSessions), items: file.sessions.sorted { $0.date < $1.date }.map {
                    (id: $0.id, label: file.title(of: $0), on: unit.sessionIds.contains($0.id))
                }) { id in model.toggle(session: id, in: unit) }
            } content: {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .unitsSessionsEmpty)) } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) { sessionRow(s) }
                            .contentShape(.rect)
                            .contextMenu { sessionMenu(s, now: now) }
                    }
                }
            }

            Block(String(localized: .unitsNotes), note: String(localized: .unitsNotesNote)) {
                Card {
                    if otherNotes.isEmpty {
                        CardRow(last: true) { EmptyLine(String(localized: .unitsNotesEmpty)) }
                    }
                    ForEach(Array(otherNotes.enumerated()), id: \.element.url) { i, note in
                        CardRow(last: i == otherNotes.count - 1) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.Palette.textTertiary)
                            Text(note.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.m)
                            Chip(note.meta.kind.label, tone: note.meta.kind == .topic ? .accent : .plain)
                        }
                        .opens(note.meta.id.map { id in { openNote(id) } })
                        .contextMenu { if let id = note.meta.id { Button(.commonOpen) { openNote(id) } } }
                    }
                }
            }

            Block(String(localized: .unitsMaterials), note: String(localized: .unitsMaterialsNote)) {
                Card {
                    if materials.isEmpty {
                        CardRow(last: true) { EmptyLine(String(localized: .unitsMaterialsEmpty)) }
                    }
                    ForEach(Array(materials.enumerated()), id: \.element.material.id) { i, item in
                        let m = item.material
                        let missing = m.status == .missing
                        CardRow(last: i == materials.count - 1) {
                            Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
                                .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text((m.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).help(m.path)
                                Text(item.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.m)
                            if missing { Chip(String(localized: .unitsFileMissing), tone: .danger) }
                        }
                        .opens(missing ? nil : { openMaterial(m) })
                        .contextMenu {
                            if !missing { Button(.commonOpen) { openMaterial(m) } }
                            #if os(macOS)
                            if !missing { Button(.unitsShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([course.store.fileURL(m.path)]) } }
                            #endif
                        }
                    }
                }
            }

            Block(String(localized: .unitsExamScope)) {
                Card(padding: Theme.Space.m) {
                    if file.exams.isEmpty {
                        EmptyLine(String(localized: .unitsExamsEmpty)).padding(.horizontal, Theme.Space.xs)
                    } else {
                        // Wraps: a course with weekly quizzes has more exams than one line holds.
                        FlowLayout(spacing: Theme.Space.s) {
                            ForEach(model.examsByDate(file)) { exam in
                                let on = exam.scopeUnitIds.contains(unit.id)
                                Button { model.toggleScope(exam, unit: unit) } label: {
                                    Label(exam.title.isEmpty ? exam.kind.label : exam.title, systemImage: on ? "checkmark" : "plus")
                                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                                        .padding(Theme.Inset.toggle)
                                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                                        .contentShape(.capsule)
                                }
                                .buttonStyle(.pointing(.plain))
                            }
                        }
                    }
                }
            }

            Block(String(localized: .unitsHistory), note: history.isEmpty ? nil : String(localized: .unitsHistoryNote)) {
                Card {
                    if history.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .unitsHistoryEmpty)) } }
                    ForEach(Array(history.enumerated()), id: \.offset) { i, entry in
                        CardRow(last: i == history.count - 1) {
                            Text(model.studyDay(entry.at).shortLabel).monospacedDigit()
                            Spacer()
                            Text(UnitsModel.minutes(entry.event.seconds)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            Chip(entry.event.result.label, tone: entry.event.result == .again ? .danger : entry.event.result == .hard ? .warning : .plain)
                        }
                    }
                }
            }

            Block(title: String(localized: .unitsEdit), note: nil, trailing: {
                Button(.unitsDeleteEllipsis, role: .destructive, action: delete).buttonStyle(.ghost).tint(Theme.Palette.danger)
            }) {
                Card {
                    FormRow(label: String(localized: .unitsFieldName)) {
                        InlineField(String(localized: .unitsFieldNamePlaceholder), text: $model.name).onSubmit { model.rename(unit) }
                    }
                    FormRow(label: String(localized: .unitsFieldParent)) {
                        SearchSelect(selection: Binding(get: { unit.parentId }, set: { model.setParent($0, of: unit) }),
                                     options: [PickOption(id: UUID?.none, title: String(localized: .unitsFieldParentNone))]
                                        + UnitTree.parentChoices(for: unit.id, in: file.units).map { PickOption(id: Optional($0.id), title: $0.title) })
                    }
                    FormRow(label: String(localized: .unitsFieldOrder), detail: String(localized: .unitsFieldOrderDetail), last: true) {
                        HStack(spacing: Theme.Space.s) {
                            Button { model.move(unit, by: -1) } label: { Image(systemName: "arrow.up") }.help(Text(.unitsMoveUp))
                            Button { model.move(unit, by: 1) } label: { Image(systemName: "arrow.down") }.help(Text(.unitsMoveDown))
                        }
                    }
                }
            }
        }
        .task(id: unit.id) { model.open(unit) }
        .onChange(of: unit.sessionIds) { model.loadNotes(unit) }
        .onChange(of: model.workspace.notesRevision) { model.loadNotes(unit) }
        .onDisappear { model.rename(unit) }
        .crumb(unit.title, level: 2, symbol: "list.bullet.indent")
        .sheet(isPresented: $reviewing) { ReviewView(workspace: model.workspace, courseId: course.id, unitId: unit.id) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.unitStep, initial: true) { _, step in reviewing = step == "review" }
        #endif
    }

    /// Date, name and topic, then the rough and review notes in the sessions page's fixed slots, so both pages read alike.
    @ViewBuilder func sessionRow(_ s: Session) -> some View {
        let file = course.file
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(s.date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
            Text(s.date.formatted(.dateTime.weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(width: 84, alignment: .leading)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(file.name(of: s)).font(Theme.Typeface.bodyStrong).strikethrough(s.isCancelled)
            if !s.topic.isEmpty {
                Text(s.topic).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        SessionNoteSlots(file: file, session: s, openNote: openNote) { if $0 == .review { openReview(s) } }
        Button { model.unlink(s, from: unit) } label: { Image(systemName: "xmark") }
            .buttonStyle(.ghost)
            .foregroundStyle(Theme.Palette.textTertiary)
            .help(Text(.unitsUnlink))
    }

    @ViewBuilder func sessionMenu(_ s: Session, now: Date) -> some View {
        if let id = s.roughNoteId { Button(.sessionsOpenRoughNote) { openNote(id) } }
        if s.reviewNoteId != nil || course.file.needsReviewNote(s, at: now) {
            Button(String(localized: s.reviewNoteId == nil ? .sessionsMakeReviewNote : .sessionsOpenReviewNote)) { openReview(s) }
        }
        Divider()
        Button(.unitsUnlinkSession) { model.unlink(s, from: unit) }
    }

    func openReview(_ s: Session) {
        if let id = model.reviewNote(of: s) { openNote(id) }
    }

    func openMaterial(_ m: FolioDomain.Material) {
        searchTarget.wrappedValue = SearchTarget(courseId: course.id, section: .materials, materialId: m.id)
    }

    /// Through the search target, which the course screen already follows to a note or a file.
    func openNote(_ id: UUID) {
        searchTarget.wrappedValue = SearchTarget(courseId: course.id, section: .notes, noteId: id)
    }
}

struct ToggleMenu: View {
    let title: String
    let items: [(id: UUID, label: String, on: Bool)]
    let toggle: (UUID) -> Void

    var body: some View {
        SearchPicker(options: items.map { PickOption(id: $0.id, title: $0.label) }, isSelected: { id in items.contains { $0.id == id && $0.on } },
                     pick: toggle, multiple: true) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "link")
                Text(title)
            }
            .font(Theme.Typeface.caption)
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Palette.fill, in: .capsule)
            .contentShape(.capsule)
        }
    }
}

extension ReviewResult {
    var label: String {
        switch self {
        case .again: String(localized: .reviewResultAgain)
        case .hard: String(localized: .reviewResultHard)
        case .good: String(localized: .reviewResultGood)
        case .easy: String(localized: .reviewResultEasy)
        case .skip: String(localized: .reviewResultSkip)
        }
    }
}
