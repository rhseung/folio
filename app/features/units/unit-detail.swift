import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitDetail: View {
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    @Bindable var model: UnitsModel
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    let delete: () -> Void

    var body: some View {
        let file = course.file
        let readiness = model.study?.readiness(of: unit.id) ?? UnitReadiness(state: .noVerdict, score: nil)
        let sessions = model.sessions(of: unit, in: file)
        let otherNotes = model.otherNotes(unit, in: file)
        let materials = model.materials(unit, in: file)
        let lectures = model.lectureRows(unit, in: file)
        let problems = model.problemRows(unit)
        let cards = model.cardLines(unit)
        Page {
            FoldingRow(labelRoom: Theme.Size.pageHeaderRoom) {
                PageHeader(title: unit.title, subtitle: model.studySubtitle(unit, in: file)) {
                    ReadinessBadge(readiness: readiness)
                }
            } control: {
                Button(unit.isDone ? .unitsDoneUndo : .unitsDone, systemImage: unit.isDone ? "arrow.uturn.backward" : "checkmark") {
                    model.toggleDone(unit)
                }
                .buttonStyle(.secondary)
                PageMenuButton { UnitMenu(courseId: course.id, unitId: unit.id, host: .own) }
            }

            readinessCard(readiness, file: file)

            if !lectures.isEmpty {
                Block(String(localized: .unitsLectures), note: model.lecturesNote(lectures)) {
                    Card {
                        ForEach(Array(lectures.enumerated()), id: \.element.id) { i, row in
                            CardRow(last: i == lectures.count - 1) {
                                Image(systemName: "doc.richtext").foregroundStyle(Theme.Palette.textSecondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    FileName((row.material.path as NSString).lastPathComponent, isFolder: false, help: row.material.path)
                                    Text(.unitsLecturePages(row.range.lowerBound, row.range.upperBound))
                                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
                                .layoutPriority(1)
                                Spacer(minLength: Theme.Space.m)
                                SeenPagesBar(seen: row.seen)
                            }
                            .opens { openMaterial(row.material, page: row.firstUnseen) }
                        }
                    }
                }
            }

            Block(title: String(localized: .unitsProblems), note: model.problemsNote(problems)) {
                Button(.unitsSolve, systemImage: "play.fill") { solve([]) }.buttonStyle(.ghost).disabled(problems.isEmpty)
            } content: {
                Card {
                    ForEach(problems) { row in
                        CardRow {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(row.title).lineLimit(1)
                                Text(row.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.m)
                            if let chip = row.chip { Badge(chip.text, tone: chip.tone) }
                        }
                        .opens { solve([row.id]) }
                    }
                    CardRow(last: true) {
                        Image(systemName: "sparkle").foregroundStyle(accent.ink).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(.unitsMakeProblems).foregroundStyle(accent.ink)
                            Text(.unitsMakeProblemsDetail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .opens { sheets.present(.makeProblems(course: course.id, unit: unit.id)) }
                }
            }

            Block(title: String(localized: .unitsCards), note: model.cardsNote(cards)) {
                Button(.unitsFlip, systemImage: "play.fill") { sheets.present(.flipCards(course: course.id, unit: unit.id)) }
                    .buttonStyle(.ghost).disabled(cards.isEmpty)
            } content: {
                Card {
                    ForEach(cards) { row in
                        CardRow {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                StudyText(text: row.record.card.front).lineLimit(1)
                                Text(row.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.m)
                            if row.changed { Badge(String(localized: .cardsSourceChanged), tone: .warning) }
                            if let chip = row.chip { Badge(chip.text, tone: chip.tone) }
                        }
                        .opens { sheets.present(.card(course: course.id, draft: CardDraft(row.record.card))) }
                        .contextMenu { CardMenu(courseId: course.id, card: row.record.card) }
                    }
                    CardRow(last: true) {
                        Image(systemName: "plus").foregroundStyle(accent.ink).accessibilityHidden(true)
                        Text(.unitsAddCard).foregroundStyle(accent.ink)
                        Spacer(minLength: 0)
                        Button(.cardsAddClaude, systemImage: "sparkles") { sheets.present(.suggestCards(course: course.id, unit: unit.id)) }
                            .buttonStyle(.ghost)
                    }
                    .opens { sheets.present(.card(course: course.id, draft: CardDraft(unitId: unit.id))) }
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
                            Badge(note.meta.kind.label, tone: note.meta.kind == .unit ? .accent : .plain)
                        }
                        .opens(note.meta.id.map { id in { openNote(id) } })
                        .contextMenu { if let id = note.meta.id { Button(.commonOpen) { openNote(id) } } }
                    }
                }
            }

            Block(
                title: String(localized: .unitsSessionsBlock), note: sessions.isEmpty ? nil : String(localized: .unitsTimes(sessions.count))
            ) {
                ToggleMenu(title: String(localized: .unitsLinkSessions), items: model.linkMenu(unit, in: file)) { id in
                    model.toggle(session: id, in: unit)
                }
            } content: {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .unitsSessionsEmpty)) } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) { sessionRow(s) }
                            .contentShape(.rect)
                            .contextMenu { SessionMenu(courseId: course.id, sessionId: s.id, host: .unit(unit.id), openNote: openNote) }
                    }
                }
            }

            Block(title: String(localized: .unitsMaterials), note: String(localized: .unitsMaterialsNote)) {
                ToggleMenu(title: String(localized: .unitsLinkMaterials), items: model.materialMenu(unit, in: file)) { id in
                    model.toggle(material: id, in: unit, file: file)
                }
            } content: {
                Card {
                    if materials.isEmpty {
                        CardRow(last: true) { EmptyLine(String(localized: .unitsMaterialsEmpty)) }
                    }
                    ForEach(Array(materials.enumerated()), id: \.element.material.id) { i, item in
                        materialRow(item, last: i == materials.count - 1)
                    }
                }
            }

            Block(String(localized: .unitsExamScope)) {
                Card(padding: Theme.Space.m) {
                    if file.exams.isEmpty {
                        EmptyLine(String(localized: .unitsExamsEmpty)).padding(.horizontal, Theme.Space.xs)
                    } else {
                        FlowLayout(spacing: Theme.Space.s) {
                            ForEach(model.examsByDate(file)) { exam in scopeChip(exam) }
                        }
                    }
                }
            }

            editBlock(file)
        }
        .task(id: unit.id) { model.open(unit) }
        .onChange(of: unit.sessionIds) { model.loadNotes(unit) }
        .onChange(of: model.workspace.notesRevision) { model.loadNotes(unit) }
        .onDisappear { model.rename(unit) }
        .crumb(unit.title, level: 2, symbol: "list.bullet.indent")
    }

    @ViewBuilder func readinessCard(_ r: UnitReadiness, file: CourseFile) -> some View {
        let concepts = model.conceptRows(r, in: file)
        Card {
            CardRow(last: concepts.isEmpty) {
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text(model.readinessLine(r)).font(Theme.Typeface.bodyStrong)
                    ProgressBar(value: r.score ?? 0).frame(maxWidth: Theme.Size.examMeter)
                    Text(model.readinessDetail(unit)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ForEach(Array(concepts.enumerated()), id: \.element.material.id) { i, row in
                CardRow(last: i == concepts.count - 1) {
                    Image(systemName: "lightbulb").foregroundStyle(Theme.Palette.warning).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(
                            .unitReadinessConcept((row.material.path as NSString).lastPathComponent, UnitsModel.pageList(row.pages))
                        )
                        .lineLimit(1)
                        Text(.unitReadinessConceptDetail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.m)
                    Button(.unitReadinessOpenLecture) { openMaterial(row.material, page: row.pages.first) }.buttonStyle(.secondary)
                }
            }
        }
    }

    func materialRow(_ item: UnitsModel.MaterialRow, last: Bool) -> some View {
        let m = item.material
        let missing = m.status == .missing
        return CardRow(last: last) {
            Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
                .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                FileName((m.path as NSString).lastPathComponent, isFolder: m.isFolder, help: m.path)
                HStack(spacing: Theme.Space.s) {
                    if let pages = item.pages {
                        SectionProgress(file: course.file, material: m.id, range: pages).fixedSize()
                    }
                    Text(item.detail).lineLimit(1)
                }
                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: Theme.Space.m)
            if !item.own {
                Badge(String(localized: .commonViaSessions)).help(Text(.unitsViaSessionsHelp))
            }
            if missing { Badge(String(localized: .unitsFileMissing), tone: .danger) }
        }
        .opens(missing ? nil : { openMaterial(m, page: nil) })
        .contextMenu { MaterialMenu(courseId: course.id, materialId: m.id, host: .unit(unit.id)) }
    }

    func scopeChip(_ exam: Exam) -> some View {
        let on = exam.scopeUnitIds.contains(unit.id)
        return Button {
            model.toggleScope(exam, unit: unit)
        } label: {
            Label(exam.title, systemImage: on ? "checkmark" : "plus")
                .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                .padding(Theme.Inset.toggle)
                .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.pointing(.plain))
    }

    func editBlock(_ file: CourseFile) -> some View {
        Block(
            title: String(localized: .unitsEdit), note: nil
        ) {
            Button(.unitsDeleteEllipsis, role: .destructive, action: delete).buttonStyle(.ghost).tint(Theme.Palette.danger)
        } content: {
            Card {
                FormRow(label: String(localized: .unitsFieldName)) {
                    InlineField(String(localized: .unitsFieldNamePlaceholder), text: $model.name).onSubmit { model.rename(unit) }
                }
                FormRow(label: String(localized: .unitsFieldParent)) {
                    Combobox(
                        selection: Binding(get: { unit.parentId }, set: { model.setParent($0, of: unit) }),
                        options: [SelectOption(id: UUID?.none, label: String(localized: .unitsFieldParentNone))]
                            + UnitTree.parentChoices(for: unit.id, in: file.units).map {
                                SelectOption(id: Optional($0.id), label: $0.title)
                            })
                }
                FormRow(label: String(localized: .unitsFieldOrder), detail: String(localized: .unitsFieldOrderDetail), last: true) {
                    HStack(spacing: Theme.Space.s) {
                        Button {
                            model.move(unit, by: -1)
                        } label: {
                            Image(systemName: "arrow.up").accessibilityLabel(Text(.unitsMoveUp))
                        }.help(Text(.unitsMoveUp))
                        Button {
                            model.move(unit, by: 1)
                        } label: {
                            Image(systemName: "arrow.down").accessibilityLabel(Text(.unitsMoveDown))
                        }.help(Text(.unitsMoveDown))
                    }
                }
            }
        }
    }

    @ViewBuilder func sessionRow(_ s: Session) -> some View {
        let file = course.file
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(s.date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
            HStack(spacing: Theme.Space.xs) {
                Text(s.date.formatted(.dateTime.weekday())).foregroundStyle(Theme.Palette.textTertiary)
                if s.kind == .makeup { Text(.sessionsMakeup).fontWeight(.semibold).foregroundStyle(accent.ink) }
            }
            .font(Theme.Typeface.caption)
        }
        .frame(width: Theme.Size.dateColumn, alignment: .leading)
        let title = model.classTitle(s, besides: unit, in: file)
        Text(title ?? String(localized: .sessionsClass))
            .font(Theme.Typeface.bodyStrong).foregroundStyle(title == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
            .strikethrough(s.isCancelled).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        SessionNoteSlots(file: file, session: s, openNote: openNote) { if $0 == .review { openReview(s) } }
        Button {
            model.unlink(s, from: unit)
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.ghost)
        .foregroundStyle(Theme.Palette.textTertiary)
        .help(Text(.unitsUnlink))
    }

    func solve(_ problems: [UUID]) {
        sheets.present(.solve(SolveRequest(course: course.id, units: [unit.id], problems: problems)))
    }

    func openReview(_ s: Session) {
        if let id = model.reviewNote(of: s) { openNote(id) }
    }

    func openMaterial(_ m: FolioDomain.Material, page: Int?) {
        openLink(AppLink(.material, m.id, anchor: page.map(AppLink.Anchor.page)), course: course.id)
    }

    func openNote(_ id: UUID) {
        openLink(AppLink(.note, id), course: course.id)
    }
}
