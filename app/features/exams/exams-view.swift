import FolioActions
import FolioCore
import FolioDomain
import SwiftUI

struct ExamsView: View {
    @State private var model: ExamsModel
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink

    static let dateColumn: CGFloat = 104

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: ExamsModel(workspace: workspace, course: course))
    }

    var body: some View {
        let now = model.workspace.now
        let (coming, past) = model.exams(now: now)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .examsTitle), subtitle: model.subtitle(coming: coming.count, past: past.count))
                Spacer()
                Button(.examsAdd) { model.add() }
                    .buttonStyle(.prominent)
            }
            if coming.isEmpty && past.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .examsEmpty)) } }
            }
            ForEach(coming) { exam in
                section(exam).linkTarget(exam.id)
            }
            if !past.isEmpty {
                Block(String(localized: .examsPast), note: "\(past.count)") {
                    Card {
                        ForEach(Array(past.enumerated()), id: \.element.id) { i, exam in
                            CardRow(last: i == past.count - 1) { pastRow(exam) }
                                .linkTarget(exam.id)
                                .contentShape(.rect)
                                .contextMenu { actions(exam) }
                                .fileDrop { model.drop($0, on: exam) }
                        }
                    }
                }
            }
        }
        .sheet(item: $model.editing) { ExamEditor(workspace: model.workspace, course: model.course, exam: $0) }
        .confirming($model.pending)
        .task(id: model.course.id) { model.load() }
        .onChange(of: model.workspace.notesRevision) { model.load() }
    }

    func section(_ exam: Exam) -> some View {
        Block(title: exam.title, note: model.component(of: exam)) {
            if let start = exam.start { DdayBadge(days: model.days(to: start), urgency: model.workspace.settings.urgency) }
        } content: {
            Card {
                CardRow {
                    when(exam, muted: false)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.m) {
                            fact("mappin.and.ellipse", exam.location, empty: String(localized: .examsNoLocation))
                            if !exam.allowed.isEmpty { fact("doc.text", exam.allowed, empty: "") }
                        }
                        if !exam.memo.isEmpty {
                            Text(exam.memo).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    summaryButton(exam)
                    menu(exam)
                }
                scope(exam)
                let linked = model.linkedMaterials(exam)
                CardRow(last: linked.isEmpty) {
                    if let folder = model.folder(of: exam) {
                        Label(folder, systemImage: "folder").foregroundStyle(Theme.Palette.textSecondary)
                        Text(model.folderDetail(exam))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                    } else if !linked.isEmpty {
                        Text(.examsLinkedMaterials).font(Theme.Typeface.bodyStrong)
                    }
                    Spacer(minLength: 0)
                    ToggleMenu(title: String(localized: .examsLinkMaterials), items: model.materialMenu(exam)) { id in
                        model.toggle(material: id, in: exam)
                    }
                }
                ForEach(Array(linked.enumerated()), id: \.element.id) { i, m in
                    CardRow(last: i == linked.count - 1) {
                        Image(systemName: m.isFolder ? "folder" : m.isPDF ? "doc.richtext" : "doc").foregroundStyle(
                            Theme.Palette.textTertiary)
                        FileName((m.path as NSString).lastPathComponent, isFolder: m.isFolder, help: m.path).layoutPriority(1)
                        Text((m.path as NSString).deletingLastPathComponent)
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .opens(m.status == .missing ? nil : { openMaterial(m) })
                    .contextMenu { MaterialMenu(courseId: model.course.id, materialId: m.id, host: .exam(exam.id)) }
                }
            }
            .contextMenu { actions(exam) }
            .fileDrop { model.drop($0, on: exam) }
            ExamPlanCard(model: model, exam: exam)
        }
    }

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

    @ViewBuilder func scope(_ exam: Exam) -> some View {
        let scope = model.scope(exam)
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
                    Text(.examsOnTrack(scope.ready, scope.units.count)).font(Theme.Typeface.caption).foregroundStyle(
                        Theme.Palette.textSecondary
                    ).monospacedDigit()
                        .help(Text(.examsOnTrackHelp))
                }
                ProgressBar(value: Double(scope.ready) / Double(scope.units.count), height: 4)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.l, alignment: .leading)], alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(Array(scope.tops.enumerated()), id: \.element.unit.id) { i, top in
                        HStack(spacing: Theme.Space.s) {
                            Text("\(i + 1)").font(Theme.Typeface.label).monospacedDigit().foregroundStyle(accent.ink)
                                .frame(width: Theme.Size.indexColumn, alignment: .trailing)
                            StudyText(text: top.unit.title, look: .title).lineLimit(1)
                            if top.children > 0 {
                                Text("+\(top.children)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                            if let readiness = scope.readiness[top.unit.id] { ReadinessBadge(readiness: readiness) }
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

    func openMaterial(_ m: FolioDomain.Material) {
        openLink(AppLink(.material, m.id), course: model.course.id)
    }

    func openSummary(_ exam: Exam) {
        if let id = model.openSummary(exam) { openLink(AppLink(.note, id), course: model.course.id) }
    }

    func actions(_ exam: Exam) -> some View {
        ExamMenu(courseId: model.course.id, examId: exam.id, host: .own, summary: .some(model.notes[exam.id]))
    }

    func menu(_ exam: Exam) -> some View {
        Menu {
            actions(exam)
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.Size.inlineButton, height: Theme.Size.inlineButton).contentShape(.rect)
                .accessibilityLabel(Text(.examsMenuHelp))
        }
        .menuButton(tinted: true, indicator: .hidden)
        .fixedSize()
        .help(Text(.examsMenuHelp))
    }

    func fact(_ symbol: String, _ text: String, empty: String) -> some View {
        Label(text.isEmpty ? empty : text, systemImage: symbol)
            .font(Theme.Typeface.caption).lineLimit(1)
            .foregroundStyle(text.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
    }
}
