import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitDetail: View {
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink
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
                Button {
                    reviewing = true
                } label: {
                    Label(.unitsStartReview, systemImage: "play.fill")
                }
                .buttonStyle(.prominent)
                .controlSize(.large)
                PageMenuButton { UnitMenu(courseId: course.id, unitId: unit.id, host: .own) }
            }

            StatStrip(items: model.stats(unit, state: state, reviews: history.count))

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
                            Chip(note.meta.kind.label, tone: note.meta.kind == .unit ? .accent : .plain)
                        }
                        .opens(note.meta.id.map { id in { openNote(id) } })
                        .contextMenu { if let id = note.meta.id { Button(.commonOpen) { openNote(id) } } }
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
                        let m = item.material
                        let missing = m.status == .missing
                        CardRow(last: i == materials.count - 1) {
                            Image(
                                systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc"
                            )
                            .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text((m.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).help(m.path)
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
                                Chip(String(localized: .commonViaSessions)).help(Text(.unitsViaSessionsHelp))
                            }
                            if missing { Chip(String(localized: .unitsFileMissing), tone: .danger) }
                        }
                        .opens(missing ? nil : { openMaterial(m) })
                        .contextMenu { MaterialMenu(courseId: course.id, materialId: m.id, host: .unit(unit.id)) }
                    }
                }
            }

            Block(String(localized: .unitsExamScope)) {
                Card(padding: Theme.Space.m) {
                    if file.exams.isEmpty {
                        EmptyLine(String(localized: .unitsExamsEmpty)).padding(.horizontal, Theme.Space.xs)
                    } else {
                        FlowLayout(spacing: Theme.Space.s) {
                            ForEach(model.examsByDate(file)) { exam in
                                let on = exam.scopeUnitIds.contains(unit.id)
                                Button {
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
                            Text(UnitsModel.minutes(entry.event.seconds)).font(Theme.Typeface.caption).foregroundStyle(
                                Theme.Palette.textTertiary)
                            Chip(
                                entry.event.result.label,
                                tone: entry.event.result == .again ? .danger : entry.event.result == .hard ? .warning : .plain)
                        }
                    }
                }
            }

            Block(
                title: String(localized: .unitsEdit), note: nil,
                trailing: {
                    Button(.unitsDeleteEllipsis, role: .destructive, action: delete).buttonStyle(.ghost).tint(Theme.Palette.danger)
                }
            ) {
                Card {
                    FormRow(label: String(localized: .unitsFieldName)) {
                        InlineField(String(localized: .unitsFieldNamePlaceholder), text: $model.name).onSubmit { model.rename(unit) }
                    }
                    FormRow(label: String(localized: .unitsFieldParent)) {
                        SearchSelect(
                            selection: Binding(get: { unit.parentId }, set: { model.setParent($0, of: unit) }),
                            options: [PickOption(id: UUID?.none, title: String(localized: .unitsFieldParentNone))]
                                + UnitTree.parentChoices(for: unit.id, in: file.units).map {
                                    PickOption(id: Optional($0.id), title: $0.title)
                                })
                    }
                    FormRow(label: String(localized: .unitsFieldOrder), detail: String(localized: .unitsFieldOrderDetail), last: true) {
                        HStack(spacing: Theme.Space.s) {
                            Button {
                                model.move(unit, by: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }.help(Text(.unitsMoveUp))
                            Button {
                                model.move(unit, by: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }.help(Text(.unitsMoveDown))
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
        .frame(width: 84, alignment: .leading)
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

    func openReview(_ s: Session) {
        if let id = model.reviewNote(of: s) { openNote(id) }
    }

    func openMaterial(_ m: FolioDomain.Material) {
        openLink(AppLink(.material, m.id), course: course.id)
    }

    func openNote(_ id: UUID) {
        openLink(AppLink(.note, id), course: course.id)
    }
}
