import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct TodayView: View {
    @State private var model: TodayModel
    @Environment(\.openLink) private var openLink
    @Environment(\.openURL) private var openURL
    @Environment(\.itemSheets) private var sheets
    @State private var hoveredNote: UUID?

    init(workspace: Workspace) {
        _model = State(initialValue: TodayModel(workspace: workspace))
    }

    var body: some View {
        // 밤새 열어 둔 페이지가 새 공부일로 넘어가도록 하루 경계마다 다시 그린다.
        TimelineView(.periodic(from: model.nextDayStart, by: 86_400)) { _ in page(now: model.workspace.now) }
            .navigationTitle(.todayTitle)
    }

    func page(now: Date) -> some View {
        let day = model.day(now: now)
        return Page {
            TodayWash(model: model, courses: day.wash)
        } content: {
            TodayHeader(model: model, summary: day.summary, classes: day.classes, reviews: day.reviews)
            DayRibbonCard(model: model, summary: day.summary, classes: day.classes, go: go, openNote: openNote)
            QuickAddField(workspace: model.workspace, showsEmptyChips: true)
            wrapUpBlock(model.liveWrapUps)
            AttendanceWarnings(model: model)
            UnfiledCoursesNotice(workspace: model.workspace)
            LMSTodayNotice(workspace: model.workspace)
            agenda(day.summary)
            ExamPlanTodayBlock(workspace: model.workspace)
            reviewBlock(day.reviews, today: day.summary.studyDay)
            StudyTimeBlock(workspace: model.workspace)
        }
        .navigationSubtitle(day.summary.studyDay.description)
        .sheet(item: $model.editing) { item in
            AssignmentSheet(workspace: model.workspace, course: item.course, assignment: item.assignment) { id, placement in
                openLink(AppLink(.material, id), in: placement, course: item.course.id)
            }
        }
        .sheet(item: $model.wrappingUp) { item in
            SessionSheet(
                workspace: model.workspace, request: SessionSheetRequest(course: item.courseId, session: item.session.id, asked: true))
        }
        .confirming($model.pending)
    }

    // MARK: Wrap-up

    @ViewBuilder func wrapUpBlock(_ items: [TodayModel.WrapUp]) -> some View {
        if !items.isEmpty {
            Block(String(localized: .todayWrapUp), note: "\(items.count)") {
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        CardRow(last: i == items.count - 1) {
                            CourseMark(model.workspace, item.courseId)
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                HStack(spacing: Theme.Space.s) {
                                    Text(model.wrapUpName(item)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                    SessionKindChip(kind: item.session.kind).courseAccent(model.workspace.accent(item.courseId))
                                }
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: Theme.Space.xs) {
                                        ForEach(item.labels, id: \.self) { Chip($0) }
                                    }
                                    Text(item.line).font(Theme.Typeface.caption)
                                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).truncationMode(.tail)
                                }
                            }
                            Spacer(minLength: Theme.Space.s)
                            Button(.todayWrapUpGo) { model.wrappingUp = item }.buttonStyle(.pointing(.bordered))
                        }
                        .help(Text(.todayWrapUpHelp))
                        .contextMenu {
                            SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId))
                        }
                    }
                }
            }
        }
    }

    static let pairWidth: CGFloat = 704

    // MARK: Exams and deadlines

    @ViewBuilder func agenda(_ summary: TodaySummary) -> some View {
        if summary.exams.isEmpty && summary.deadlines.isEmpty {
            EmptyCard(
                symbol: "checkmark", tone: .success, title: String(localized: .todayAgendaEmpty),
                detail: String(localized: .todayAgendaEmptyDetail(TodaySummary.examHorizon)))
        } else {
            Fold(wideFrom: Self.pairWidth) {
                examsBlock(summary).frame(maxWidth: .infinity, alignment: .topLeading)
                deadlinesBlock(summary).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    func examsBlock(_ summary: TodaySummary) -> some View {
        let exams = summary.exams
        return Block(String(localized: .todayExams), note: String(localized: .todayExamsNote(TodaySummary.examHorizon, exams.count))) {
            if exams.isEmpty {
                EmptyCard(symbol: "calendar", title: String(localized: .todayExamsEmpty), detail: String(localized: .todayExamsEmptyDetail))
            } else {
                Card {
                    ForEach(exams, id: \.exam.id) { examRow($0) }
                }
            }
        }
    }

    func examRow(_ item: TodaySummary.ExamItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(model.dDay(item)).font(Theme.Typeface.figureCompact).foregroundStyle(DdayChip.heat(item.dDay))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.exam.title).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                    HStack(spacing: Theme.Space.xs) {
                        CourseMark(model.workspace, item.courseId, inline: true)
                        Text(model.title(item.courseId)).lineLimit(1)
                    }
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                Text(model.examStart(item)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .contentShape(.rect)
        .opens { go(item.courseId, .exams) }
        .contextMenu { ExamMenu(courseId: item.courseId, examId: item.exam.id) }
    }

    func deadlinesBlock(_ summary: TodaySummary) -> some View {
        let (shown, more) = model.shownDeadlines(summary)
        return Block(
            title: String(localized: .todayDeadlines), note: summary.deadlines.isEmpty ? nil : "\(summary.deadlines.count)",
            trailing: {
                if more > 0 { Button(String(localized: .todayMore(more))) { model.showsAllDeadlines = true }.buttonStyle(.ghost) }
            }
        ) {
            if summary.deadlines.isEmpty {
                EmptyCard(
                    symbol: "checkmark", tone: .success, title: String(localized: .todayDeadlinesEmpty),
                    detail: String(localized: .todayDeadlinesEmptyDetail))
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(shown) { row in
                            if row.id != shown.first?.id { Theme.Palette.lineSoft.frame(height: 1) }
                            deadlineRow(row)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                }
            }
        }
    }

    func deadlineRow(_ row: TodayModel.DeadlineRow) -> some View {
        let item = row.item
        let accent = model.workspace.accent(item.courseId)
        let tone = row.tone
        return Button {
            model.edit(item)
        } label: {
            HStack(spacing: Theme.Space.s) {
                AssignmentStatusIcon(status: item.assignment.status, tint: accent.color, size: 18)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.assignment.title).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                    Text(model.title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                if let tone {
                    Chip(row.due, tone: tone, solid: row.urgency == .urgent).monospacedDigit()
                } else {
                    Text(row.due).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                        .fixedSize().padding(Theme.Inset.tag)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(tone.map { $0.fill.opacity(Theme.Opacity.toneRow) } ?? .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu { AssignmentMenu(courseId: item.courseId, assignmentId: item.assignment.id) }
    }

    // MARK: Reviews

    func reviewBlock(_ reviews: TodayModel.Reviews, today: LocalDate) -> some View {
        let left = reviews.left, done = reviews.doneToday
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Text(.todayReviews).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                if reviews.total > 0 {
                    Text(.todayReviewsProgress(done, reviews.total)).font(Theme.Typeface.caption).monospacedDigit()
                        .foregroundStyle(left == 0 ? Theme.Palette.success : Theme.Palette.textSecondary)
                    progress(reviews.fraction)
                } else {
                    Spacer(minLength: 0)
                }
                if reviews.streak > 0 {
                    Label(.todayProgressStreak(reviews.streak), systemImage: "flame.fill").labelStyle(.titleAndIcon)
                        .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.Palette.warning)
                        .symbolEffect(.bounce, value: reviews.streak)
                }
                if !reviews.all.isEmpty {
                    Button(.todayReviewsSkipAll) { model.skip(reviews.all) }
                        .buttonStyle(.ghost)
                        .font(Theme.Typeface.caption)
                }
            }
            if left == 0 {
                if done > 0 {
                    EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayReviewsDone))
                } else {
                    EmptyCard(
                        symbol: CourseMark.defaultIcon, title: String(localized: .todayReviewsEmpty),
                        detail: String(localized: .todayReviewsEmptyDetail))
                }
            } else {
                Fold(wideFrom: Self.pairWidth) {
                    notesList(reviews.notes, today: today).frame(maxWidth: .infinity, alignment: .topLeading)
                    unitsList(reviews.queue).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            deferredList(reviews.deferred)
        }
    }

    func progress(_ fraction: Double) -> some View {
        Capsule().fill(Theme.Palette.fill)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in Capsule().fill(Theme.Palette.success).frame(width: proxy.size.width * fraction) }
            }
            .frame(height: Theme.Space.xs)
            .animation(Theme.Motion.settle, value: fraction)
    }

    func listGroupHeader<Label: View>(first: Bool, @ViewBuilder label: () -> Label) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) { label() }
                .font(Theme.Typeface.caption.weight(.semibold))
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, first ? Theme.Space.m : Theme.Space.l)
                .padding(.bottom, Theme.Space.tight)
            Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l).padding(.bottom, Theme.Space.xs)
        }
    }

    @ViewBuilder func listMore(_ more: Int, show: @escaping () -> Void) -> some View {
        if more > 0 {
            Button(String(localized: .todayMore(more)), action: show)
                .buttonStyle(.ghost)
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, Theme.Space.m)
        } else {
            Color.clear.frame(height: Theme.Space.s)
        }
    }

    func notesList(_ notes: [TodaySummary.SessionItem], today: LocalDate) -> some View {
        let (groups, more) = model.noteGroups(notes, today: today)
        return Block(
            String(localized: .todayReviewsNotes), note: notes.isEmpty ? nil : String(localized: .todayReviewsNotesNote(notes.count))
        ) {
            if notes.isEmpty {
                EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayReviewsNotesEmpty))
            } else {
                Card {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                        listGroupHeader(first: i == 0) { Text(group.label).foregroundStyle(Theme.Palette.textSecondary) }
                        ForEach(group.items, id: \.session.id) { noteRow($0) }
                    }
                    listMore(more) { model.showsAllNotes = true }
                }
            }
        }
    }

    func noteRow(_ item: TodaySummary.SessionItem) -> some View {
        let accent = model.workspace.accent(item.courseId)
        let unfinished = item.session.reviewNoteUnfinished
        #if os(macOS)
        let hovering = hoveredNote == item.session.id
        let finishing = hovering, marked = unfinished && !hovering
        #else
        let finishing = true, marked = unfinished
        #endif
        return HStack(spacing: Theme.Space.s) {
            Button {
                if let id = model.reviewNote(of: item) { openNote(in: item.courseId)(id) }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    LineIcon(symbol: unfinished ? "doc.text" : "doc").foregroundStyle(accent.color)
                        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(model.sessionName(item.courseId, item.session)).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                        Text(model.title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(
                            1)
                    }
                    Spacer(minLength: Theme.Space.s)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(unfinished ? .todayNoteOpenHelp : .todayNoteCreateHelp))
            if marked {
                Label(.todayNoteUnfinished, systemImage: "pencil").labelStyle(GhostLabelStyle())
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
            }
            if finishing,
                let source = SessionMenu.source(
                    model.workspace, item.courseId, item.session.id, host: .elsewhere,
                    openNote: openNote(in: item.courseId), openLink: openLink, openURL: openURL, sheets: sheets),
                let review = model.review(of: item)
            {
                ItemButton(source: source, command: .review(review))
                    .buttonStyle(.ghost)
                    .font(Theme.Typeface.caption)
                    .help(Text(unfinished ? .todayNoteFinish : .todayNoteNoReviewHelp))
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.tight)
        .onHover { hoveredNote = $0 ? item.session.id : (hoveredNote == item.session.id ? nil : hoveredNote) }
        .contextMenu {
            SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId))
        }
    }

    func unitsList(_ queue: [Workspace.ReviewEntry]) -> some View {
        let groups = model.unitGroups(queue)
        return Block(String(localized: .todayReviewsUnits), note: queue.isEmpty ? nil : "\(queue.count)") {
            if queue.isEmpty {
                EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayReviewsUnitsEmpty))
            } else {
                Card {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                        let (shown, more) = model.shownUnits(group)
                        listGroupHeader(first: i == 0) {
                            CourseMark(model.workspace, group.courseId, inline: true)
                            Text(model.title(group.courseId)).foregroundStyle(Theme.Palette.text).lineLimit(1).layoutPriority(1)
                            if group.writeNoteFirst {
                                Text(.todayReviewsAfterNote).fontWeight(.regular).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.s)
                            if group.overdue > 0 {
                                Text(.todayReviewsOverdue(group.overdue)).fontWeight(.bold).foregroundStyle(Theme.Palette.danger)
                                    .fixedSize()
                            }
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.entry.item.unitId) { n, pair in
                            unitRow(pair.entry, number: n + 1, then: queue[(pair.index + 1)...])
                        }
                        if more > 0 {
                            listMore(more) { model.expandedUnitGroups.insert(group.courseId) }
                        }
                    }
                    if let last = groups.last, model.shownUnits(last).more == 0 { Color.clear.frame(height: Theme.Space.s) }
                }
            }
        }
    }

    func unitRow(_ entry: Workspace.ReviewEntry, number: Int, then rest: ArraySlice<Workspace.ReviewEntry>) -> some View {
        let waiting = entry.item.writeNoteFirst
        return ReviewOpener(
            courseId: entry.courseId, unitId: entry.item.unitId,
            then: rest.map { .init(courseId: $0.courseId, unitId: $0.item.unitId) }
        ) {
            HStack(spacing: Theme.Space.s) {
                Text("\(number)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                Text(entry.unitTitle).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                if !waiting { Image(systemName: "chevron.right").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.tight)
            .opacity(waiting ? Theme.Opacity.ended : 1)
            .contentShape(.rect)
        }
        .contextMenu { reviewMenu(entry) }
    }

    @ViewBuilder func deferredList(_ deferred: [Workspace.ReviewEntry]) -> some View {
        if !deferred.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(.todayReviewsDeferred).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textSecondary)
                ForEach(deferred, id: \.item.unitId) { entry in
                    ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId) {
                        HStack(spacing: Theme.Space.m) {
                            CourseMark(model.workspace, entry.courseId)
                            Text(entry.unitTitle)
                            Spacer()
                            Text(model.title(entry.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .contextMenu { reviewMenu(entry) }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.Palette.column, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    func reviewMenu(_ entry: Workspace.ReviewEntry) -> some View {
        UnitMenu(courseId: entry.courseId, unitId: entry.item.unitId)
    }

    func go(_ course: UUID, _ section: CourseSection) {
        openLink(.course(course, page: section.page), course: course)
    }

    func openNote(in course: UUID) -> (UUID) -> Void {
        { openLink(AppLink(.note, $0), course: course) }
    }
}

#if DEBUG
import FolioFixtures

@MainActor private func todayPreview(_ scenario: Scenario) -> some View {
    let workspace = try! Workspace.scenario(scenario)
    return TodayView(workspace: workspace).environment(workspace)
}

#Preview("바쁜 날", traits: .fixedLayout(width: 1180, height: 1600)) { todayPreview(.busyDay) }
#Preview("바쁜 날, 좁게", traits: .fixedLayout(width: 720, height: 2000)) { todayPreview(.busyDay) }
#Preview("시험이 몰린 날", traits: .fixedLayout(width: 1180, height: 1600)) { todayPreview(.manyExams) }
#Preview("한가한 날", traits: .fixedLayout(width: 1180, height: 1000)) { todayPreview(.quietDay) }
#Preview("빈 학기", traits: .fixedLayout(width: 1180, height: 800)) { todayPreview(.empty) }
#endif
