import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitsView: View {
    @State private var model: UnitsModel
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let course: LoadedCourse
    let place: AppLink
    let opened: (UUID?) -> Void

    init(workspace: Workspace, course: LoadedCourse, place: AppLink, opened: @escaping (UUID?) -> Void) {
        let model = UnitsModel(workspace: workspace, courseId: course.id)
        // 아래의 첫 보고보다 먼저 정해야 한다. 그러지 않으면 창에 목록이 보인다고 알린다.
        if let pick = place.selection(of: .unit) { model.openUnit = pick }
        _model = State(initialValue: model)
        self.course = course
        self.place = place
        self.opened = opened
    }

    var body: some View {
        Group {
            if let id = model.openUnit, let unit = course.file.units.first(where: { $0.id == id }) {
                UnitDetail(model: model, course: course, unit: unit, delete: { model.remove(unit) })
            } else {
                list
            }
        }
        .task(id: [model.workspace.notesRevision, model.workspace.studyRevision]) { model.loadNoteCounts() }
        // 페이지는 목록에서 시작하고 지난번에 연 단원은 모델과 함께 사라졌으므로 initial로도 부른다.
        .onChange(of: model.openUnit, initial: true) { _, id in opened(id) }
        .onChange(of: place) { _, link in
            if let pick = link.selection(of: .unit) { model.openUnit = pick }
        }
        .confirming($model.pending)
    }

    var list: some View {
        let file = course.file
        let exam = model.nextExam
        let rows = model.rows(in: exam)
        let unlinked = file.sessionsNeedingUnits(at: model.workspace.now)
        return Page {
            PageHeader(title: String(localized: .unitsTitle), subtitle: model.subtitle(file)) { EmptyView() }
            if let exam, let card = model.examCard(exam) { examCard(card) }
            if !unlinked.isEmpty { unlinkedCard(unlinked) }
            if let exam, !exam.plan.isEmpty { planBlock(exam) }
            if let exam {
                Block(String(localized: .unitsScope(exam.title)), note: "\(rows.scope.count)") { unitCard(rows.scope) }
                if !rows.rest.isEmpty {
                    Block(String(localized: .unitsOther), note: "\(rows.rest.count)") { unitCard(rows.rest) }
                }
            } else if !rows.rest.isEmpty {
                unitCard(rows.rest)
            }
            Card {
                CardRow(last: true) {
                    Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary).accessibilityHidden(true)
                    TextField(String(localized: .unitsNewName), text: $model.newTitle).textFieldStyle(.plain).onSubmit(model.add)
                    Button(.commonAdd, action: model.add).buttonStyle(.prominent).disabled(!model.canAdd)
                }
            }
            if file.units.isEmpty {
                EmptyLine(String(localized: .unitsEmpty))
                    .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    func examCard(_ card: UnitsModel.ExamCard) -> some View {
        Card {
            CardRow(last: card.few.isEmpty) {
                ExamDateTile(date: card.exam.start, tone: model.examTone(card.days))
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text(card.exam.title).font(Theme.Typeface.figureMedium).lineLimit(1)
                    ProgressBar(value: card.readiness.fraction).frame(maxWidth: Theme.Size.examMeter)
                    Text(card.line).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.m)
                DdayBadge(days: card.days, urgency: model.workspace.settings.urgency)
            }
            ForEach(Array(card.few.enumerated()), id: \.element.unit.id) { i, few in
                CardRow(last: i == card.few.count - 1) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.textTertiary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(.unitsFewProblems(few.unit.title, few.problems)).lineLimit(1)
                        Text(.unitsFewProblemsDetail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.m)
                    Button(.unitsMakeProblems, systemImage: "sparkle") {
                        sheets.present(.makeProblems(course: course.id, unit: few.unit.id, count: few.missing))
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
    }

    func planBlock(_ exam: Exam) -> some View {
        let rows = model.planRows(exam)
        return Block(
            title: String(localized: .unitsPlan), note: model.planNote(exam)
        ) {
            Button(.unitsPlanEdit) { openLink(.course(course.id, page: .exams), course: course.id) }.buttonStyle(.ghost)
        } content: {
            Card {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    CardRow(last: i == rows.count - 1) {
                        Text(row.day)
                            .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(row.isToday ? Theme.Palette.text : Theme.Palette.textSecondary)
                            .frame(width: Theme.Size.pagesColumn, alignment: .leading)
                        Checkbox(isOn: row.done) { model.togglePlan(row) }
                            .help(Text(row.done ? .examsPlanUndo : .examsPlanCheck))
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(row.title).lineLimit(1).strikethrough(row.done, color: Theme.Palette.textTertiary)
                                .foregroundStyle(row.done ? Theme.Palette.textTertiary : Theme.Palette.text)
                            if !row.detail.isEmpty {
                                Text(row.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if let solve = row.solve, !row.done { PlanSolveButton(course: course.id, item: row.item.id, solve: solve) }
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        PlanItemMenu(courseId: course.id, examId: exam.id, item: row.item.id, done: row.done) { model.togglePlan(row) }
                    }
                }
            }
        }
    }

    func unitCard(_ rows: [UnitsModel.Row]) -> some View {
        Card {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                CardRow(last: i == rows.count - 1) {
                    DoneToggle(done: row.unit.isDone) { model.toggleDone(row.unit) }
                    Button {
                        model.openUnit = row.unit.id
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(row.unit.title).lineLimit(1)
                                HStack(spacing: Theme.Space.xs) {
                                    Text(row.parts.joined(separator: " · "))
                                    if let wrong = row.wrong { Text("· " + wrong).foregroundStyle(Theme.Palette.danger) }
                                }
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                                if !row.pages.isEmpty { SeenPagesBar(seen: row.pages).padding(.top, Theme.Space.xs) }
                            }
                            Spacer(minLength: Theme.Space.m)
                            ReadinessBadge(readiness: row.readiness)
                        }
                        .padding(.leading, CGFloat(row.depth) * Theme.Space.xl)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                    PageMenuButton { UnitMenu(courseId: course.id, unitId: row.unit.id, host: .list) }
                }
                .contextMenu { UnitMenu(courseId: course.id, unitId: row.unit.id, host: .list) }
            }
        }
    }

    func unlinkedCard(_ sessions: [Session]) -> some View {
        let shown = sessions.prefix(6)
        return NoticeCard(
            title: String(localized: .unitsUnlinkedTitle(sessions.count)),
            detail: String(localized: .unitsUnlinkedDetail),
            systemImage: "link.badge.plus"
        ) {
            EmptyView()
        } rows: {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && sessions.count <= shown.count) {
                    Text(course.file.title(of: s, calendar: model.workspace.calendar)).lineLimit(1)
                    Spacer(minLength: Theme.Space.m)
                    SessionUnitsButton(course: course, session: s)
                }
            }
            if sessions.count > shown.count {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(sessions.count - shown.count))) }
            }
        }
    }
}

extension LocalDate {
    var shortLabel: String {
        date(in: .current)?.formatted(.dateTime.month().day().weekday()) ?? description
    }
}
