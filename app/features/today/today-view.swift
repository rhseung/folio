import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct TodayView: View {
    @State private var model: TodayModel
    @Environment(\.searchTarget) private var searchTarget
    @State private var skippingAll = false
    @State private var wide = true
    @State private var hoveredNote: UUID?

    init(workspace: Workspace) {
        _model = State(initialValue: TodayModel(workspace: workspace))
    }

    var body: some View {
        // Redrawn at each day boundary, so a page left open overnight turns to the new study day.
        TimelineView(.periodic(from: model.nextDayStart, by: 86_400)) { _ in page(now: model.workspace.now) }
            .navigationTitle(.todayTitle)
    }

    func page(now: Date) -> some View {
        let summary = model.summary(now: now)
        let reviews = model.reviews(now: now)
        let classes = model.ribbonClasses(summary, now: now)
        return Page {
            TodayWash(model: model, courses: model.washCourses(summary, now: now))
        } content: {
            TodayHeader(model: model, summary: summary, classes: classes, reviews: reviews)
            DayRibbonCard(model: model, summary: summary, classes: classes, go: go, openNote: openNote)

            // One slot for both: an empty NowClassCard still took a stack slot and left a double gap above the field.
            VStack(alignment: .leading, spacing: 0) {
                NowClassCard(model: model, studyDay: summary.studyDay)
                QuickAddField(workspace: model.workspace)
            }

            AttendanceWarnings(model: model)
            agenda(summary)
            ExamPlanTodayBlock(courses: model.current)
            reviewBlock(reviews, notes: summary.missingReviewNotes, today: summary.studyDay)
            StudyTimeBlock(workspace: model.workspace)
        }
        .navigationSubtitle(summary.studyDay.description)
        .sheet(item: $model.editing) { AssignmentSheet(workspace: model.workspace, course: $0.course, assignment: $0.assignment) }
    }

    // MARK: Exams and deadlines

    /// Exams and deadlines side by side, the two things with a date on them. Both empty, they say so once.
    @ViewBuilder func agenda(_ summary: TodaySummary) -> some View {
        if summary.exams.isEmpty && summary.deadlines.isEmpty {
            EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayAgendaEmpty),
                      detail: String(localized: .todayAgendaEmptyDetail(TodaySummary.examHorizon)))
        } else {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: Theme.Space.xl) {
                        examsBlock(summary).frame(maxWidth: .infinity, alignment: .topLeading)
                        deadlinesBlock(summary).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.section) {
                        examsBlock(summary)
                        deadlinesBlock(summary)
                    }
                }
            }
            // Below this a half column cuts a course name off after a word.
            .onGeometryChange(for: Bool.self) { $0.size.width >= 640 } action: { wide = $0 }
        }
    }

    func examsBlock(_ summary: TodaySummary) -> some View {
        let exams = summary.exams
        return Block(String(localized: .todayExams), note: String(localized: .todayExamsNote(TodaySummary.examHorizon, exams.count))) {
            if exams.isEmpty {
                EmptyCard(symbol: "calendar", title: String(localized: .todayExamsEmpty), detail: String(localized: .todayExamsEmptyDetail))
            } else {
                // Spaced like the to-do list beside it: no rules between rows, air instead.
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
        .contextMenu { Button(.commonShowExams, systemImage: "calendar.badge.exclamationmark") { go(item.courseId, .exams) } }
    }

    func deadlinesBlock(_ summary: TodaySummary) -> some View {
        let groups = model.deadlineGroups(summary.deadlines, studyDay: summary.studyDay)
        let (shown, more) = model.shownDeadlines(groups)
        return Block(String(localized: .todayDeadlines), note: summary.deadlines.isEmpty ? nil : "\(summary.deadlines.count)") {
            if summary.deadlines.isEmpty {
                EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayDeadlinesEmpty),
                          detail: String(localized: .todayDeadlinesEmptyDetail))
            } else {
                Card {
                    // Packed like a reminders list: a rule under each group's name, none between rows.
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, group in
                        listGroupHeader(first: i == 0) {
                            Text(model.groupLabel(group.when))
                                .foregroundStyle(group.when == .today ? Theme.Palette.danger : Theme.Palette.textSecondary)
                        }
                        ForEach(group.items, id: \.assignment.id) { deadlineRow($0) }
                    }
                    listMore(more) { model.showsAllDeadlines = true }
                }
            }
        }
    }

    func deadlineRow(_ item: TodaySummary.DeadlineItem) -> some View {
        let accent = model.workspace.accent(item.courseId)
        return Button { model.edit(item) } label: {
            HStack(spacing: Theme.Space.s) {
                AssignmentStatusIcon(status: item.assignment.status, tint: accent.color, size: 18)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.assignment.title).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                    Text(model.title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text(model.due(item)).font(Theme.Typeface.caption.weight(item.isToday ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(item.isToday ? Theme.Palette.danger : Theme.Palette.textSecondary).fixedSize()
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.tight)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu {
            Button(.commonEditEllipsis) { model.edit(item) }
            Button(.todayDeadlinesShow, systemImage: "checklist") { go(item.courseId, .assignments) }
        }
    }

    // MARK: Reviews

    /// A class's review note comes first, then the units: writing the note is the day's review of that class
    /// (docs/SPEC.md "복습 스케줄러"), and a unit linked to it waits on the note anyway.
    func reviewBlock(_ reviews: TodayModel.Reviews, notes: [TodaySummary.SessionItem], today: LocalDate) -> some View {
        let queue = reviews.queue, all = reviews.all
        let left = queue.count + notes.count, done = reviews.doneToday
        // A list title right under the progress line read as its caption; a step more keeps the line over both lists.
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Text(.todayReviews).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                if left + done > 0 {
                    Text(.todayReviewsProgress(done, done + left)).font(Theme.Typeface.caption).monospacedDigit()
                        .foregroundStyle(left == 0 ? Theme.Palette.success : Theme.Palette.textSecondary)
                    progress(Double(done) / Double(done + left))
                } else {
                    Spacer(minLength: 0)
                }
                if reviews.streak > 0 {
                    Label(.todayProgressStreak(reviews.streak), systemImage: "flame.fill").labelStyle(.titleAndIcon)
                        .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.Palette.warning)
                        .symbolEffect(.bounce, value: reviews.streak)
                }
                if !all.isEmpty {
                    Button(.todayReviewsSkipAll) { skippingAll = true }
                        .buttonStyle(.ghost)
                        .font(Theme.Typeface.caption)
                        .confirmationDialog(String(localized: .todayReviewsSkipAllConfirm(all.count)), isPresented: $skippingAll) {
                            Button(.todayReviewsSkipAllButton(all.count)) { model.skip(all) }
                        } message: {
                            Text(.todayReviewsSkipAllMessage)
                        }
                }
            }
            if left == 0 {
                if done > 0 {
                    EmptyCard(symbol: "checkmark", tone: .success, title: String(localized: .todayReviewsDone))
                } else {
                    EmptyCard(symbol: CourseMark.defaultIcon, title: String(localized: .todayReviewsEmpty), detail: String(localized: .todayReviewsEmptyDetail))
                }
            } else {
                // Two lists, like exams and deadlines above: writing a class's note and reviewing units are different
                // jobs, and in one card their rows read as one kind of thing.
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: Theme.Space.xl) {
                            notesList(notes, today: today).frame(maxWidth: .infinity, alignment: .topLeading)
                            unitsList(queue).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Space.section) {
                            notesList(notes, today: today)
                            unitsList(queue)
                        }
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.size.width >= 640 } action: { wide = $0 }
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
            .animation(.snappy(duration: 0.35), value: fraction)
    }

    /// A group's name with the rule under it, as in the deadline list. 12pt from the rule to the first row sits
    /// between the 6 above it and the 16 between rows; less sat the rows on the rule, more left the name hanging.
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
        return Block(String(localized: .todayReviewsNotes), note: notes.isEmpty ? nil : String(localized: .todayReviewsNotesNote(notes.count))) {
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
        let hovering = hoveredNote == item.session.id
        return HStack(spacing: Theme.Space.s) {
            Button {
                if let id = model.reviewNote(of: item) { openNote(in: item.courseId)(id) }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    // A document, not a circle: a circle is the to-do list's checkbox, and this row opens a note.
                    LineIcon(symbol: unfinished ? "doc.text" : "doc").foregroundStyle(accent.color)
                        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(model.sessionName(item.courseId, item.session)).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                        Text(model.title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(unfinished ? .todayNoteOpenHelp : .todayNoteCreateHelp))
            // Finishing shows on hover only, so the resting list reads as notes rather than as buttons.
            if hovering {
                Button(unfinished ? String(localized: .todayNoteDone) : String(localized: .todayNoteNoReview)) {
                    unfinished ? model.finishReviewNote(item) : model.skipReviewNote(item)
                }
                .buttonStyle(.ghost)
                .font(Theme.Typeface.caption)
                .help(Text(unfinished ? .todayNoteFinish : .todayNoteNoReviewHelp))
            } else if unfinished {
                Label(.todayNoteUnfinished, systemImage: "pencil").labelStyle(GhostLabelStyle())
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.tight)
        .onHover { hoveredNote = $0 ? item.session.id : (hoveredNote == item.session.id ? nil : hoveredNote) }
        .contextMenu {
            SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId)) { go(item.courseId, .sessions) }
            Divider()
            if unfinished { Button(.todayNoteFinish, systemImage: "checkmark") { model.finishReviewNote(item) } }
            Button(.todayNoteNoReview, systemImage: "forward") { model.skipReviewNote(item) }
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
                                Text(.todayReviewsOverdue(group.overdue)).fontWeight(.bold).foregroundStyle(Theme.Palette.danger).fixedSize()
                            }
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.entry.item.unitId) { n, pair in
                            unitRow(pair.entry, number: n + 1, then: queue[(pair.index + 1)...])
                        }
                        if more > 0 {
                            listMore(more) { model.expandedUnitGroups.insert(group.courseId) }
                        }
                    }
                    // The fold link brings its own bottom margin.
                    if let last = groups.last, model.shownUnits(last).more == 0 { Color.clear.frame(height: Theme.Space.s) }
                }
            }
        }
    }

    func unitRow(_ entry: Workspace.ReviewEntry, number: Int, then rest: ArraySlice<Workspace.ReviewEntry>) -> some View {
        // Waiting on its class's note: still openable, but dimmed and without the arrow that says "start here".
        let waiting = entry.item.writeNoteFirst
        return ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId,
                            then: rest.map { .init(courseId: $0.courseId, unitId: $0.item.unitId) }) {
            HStack(spacing: Theme.Space.s) {
                Text("\(number)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    // The tile-high slot, as the note list's glyph: without it these rows came out shorter than theirs.
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
                    ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId) { HStack(spacing: Theme.Space.m) {
                        CourseMark(model.workspace, entry.courseId)
                        Text(entry.unitTitle)
                        Spacer()
                        Text(model.title(entry.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                    } }
                    .contextMenu { reviewMenu(entry) }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.Palette.column, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    @ViewBuilder func reviewMenu(_ entry: Workspace.ReviewEntry) -> some View {
        Button(.todayReviewsShowUnits, systemImage: "list.bullet") { go(entry.courseId, .units) }
        Button(.todayReviewsSkip, systemImage: "forward") { model.skip([entry]) }
    }

    func go(_ course: UUID, _ section: CourseSection) {
        searchTarget.wrappedValue = SearchTarget(courseId: course, section: section)
    }

    func openNote(in course: UUID) -> (UUID) -> Void {
        { searchTarget.wrappedValue = SearchTarget(courseId: course, section: .notes, noteId: $0) }
    }
}

struct NowClassCard: View {
    let model: TodayModel
    let studyDay: LocalDate
    @Environment(\.searchTarget) private var searchTarget

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = model.workspace.now
            if let item = model.nowClass(at: now) {
                card(item, now: now) {
                    if let suggested = item.suggested {
                        SuggestedSessionActions(item: suggested) { open(suggested.courseId, $0) }
                    } else if let sessionId = item.sessionId {
                        Button(.todayNowClassNote) { if let id = model.workspace.note(.rough, of: sessionId, in: item.courseId) { open(item.courseId, id) } }
                            .buttonStyle(.ghost)
                            .help(Text(.sessionsOpenRoughNote))
                    }
                }
            }
        }
    }

    func open(_ course: UUID, _ note: UUID) {
        searchTarget.wrappedValue = SearchTarget(courseId: course, section: .notes, noteId: note)
    }

    /// Progress lives on the day ribbon's line now; the card keeps the minutes as words.
    func card(_ item: TodayModel.NowClass, now: Date, @ViewBuilder actions: () -> some View) -> some View {
        let accent = model.workspace.accent(item.courseId)
        let next = model.nextPanel(now: now, studyDay: studyDay)
        return HStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(item.room.isEmpty ? .todayNowClass : .todayNowClassRoom(item.room)).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                    Text("\(model.title(item.courseId)) · \(item.name)").font(Theme.Typeface.figureCompact).lineLimit(1)
                    HStack(spacing: Theme.Space.tight) {
                        Text("\(model.time(item.start)) – \(model.time(item.end))").foregroundStyle(Theme.Palette.textSecondary)
                        Text("·").foregroundStyle(Theme.Palette.textTertiary)
                        Text(.todayNowClassRemaining(Int(item.end.timeIntervalSince(now) / 60) + 1)).fontWeight(.semibold).foregroundStyle(accent.ink)
                    }
                    .font(Theme.Typeface.caption).monospacedDigit()
                }
                Spacer(minLength: Theme.Space.m)
                actions()
            }
            .padding(Theme.Inset.stat)
            .frame(maxHeight: .infinity)
            .background(accent.tint)
            Theme.Palette.lineSoft.frame(width: 1)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.todayNext).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                Text(next.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                Text(next.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
            }
            .padding(Theme.Inset.stat)
            .frame(width: 200, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.Palette.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(accent.color.opacity(0.35)))
        .padding(.bottom, Theme.Space.l)
    }
}

struct DateMark: TextAttribute {}

/// Draws only rounded pills behind runs marked `DateMark`; the glyphs come from the field on top.
struct DateMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // Korean and digits come from different fonts, so one phrase spans several runs; they join into one pill.
            var pill: CGRect?
            func flush() {
                if let rect = pill?.insetBy(dx: -4, dy: -2) {
                    context.fill(RoundedRectangle(cornerRadius: Theme.Radius.small).path(in: rect), with: .color(Theme.Palette.highlightFill))
                }
                pill = nil
            }
            for run in line {
                if run[DateMark.self] != nil {
                    let rect = run.typographicBounds.rect
                    pill = pill.map { $0.union(rect) } ?? rect
                } else {
                    flush()
                }
            }
            flush()
        }
    }
}

struct QuickAddField: View {
    @State private var model: QuickAddModel

    init(workspace: Workspace, fixedCourse: UUID? = nil) {
        _model = State(initialValue: QuickAddModel(workspace: workspace, fixedCourse: fixedCourse))
    }

    var body: some View {
        let parsed = model.parsed
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary)
                TextField(String(localized: .todayQuickAddPrompt), text: $model.text)
                    .textFieldStyle(.plain)
                    .font(Theme.Typeface.bodyLarge)
                    // The marks are drawn behind the field instead of styling its text: rewriting the text while
                    // typing breaks Korean composition and eats characters.
                    .background(alignment: .leading) { marks(parsed?.dueRanges ?? []).allowsHitTesting(false) }
                    .onSubmit { if let parsed { model.add(parsed) } }
                if let parsed {
                    Button(.todayQuickAddSave) { model.add(parsed) }
                        .buttonStyle(.pointing(.glassProminent))
                        .disabled(!model.canAdd(parsed))
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .frame(height: 44)
            .floatingGlass()
            // Under the field, not inside it: beside the typed line it ran out of room and cut off the deadline.
            if let parsed { summary(parsed).padding(.leading, Theme.Inset.panel) }
        }
    }

    func summary(_ parsed: QuickAdd) -> some View {
        HStack(spacing: Theme.Space.tight) {
            if let id = parsed.courseId, let title = model.courseTitle(parsed) {
                CourseMark(model.workspace, id, inline: true)
                Text(title).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text(.todayQuickAddNoCourse).foregroundStyle(Theme.Palette.danger)
            }
            if let due = model.due(parsed) { Text("· \(due)").foregroundStyle(Theme.Palette.textTertiary) }
            if parsed.repeats == .weekly { Label(.todayQuickAddWeekly, systemImage: "repeat").foregroundStyle(Theme.Palette.textTertiary) }
            if !parsed.title.isEmpty { Text("· \(parsed.title)").foregroundStyle(Theme.Palette.textTertiary) }
        }
        .font(Theme.Typeface.caption).lineLimit(1)
    }

    /// The line laid out again under the field, invisible, so `DateMarkRenderer` can draw a pill behind the deadline words.
    func marks(_ ranges: [Range<String.Index>]) -> some View {
        let text = model.text
        var mirror = Text("")
        var at = text.startIndex
        for r in ranges {
            mirror = mirror + Text(text[at..<r.lowerBound]) + Text(text[r]).customAttribute(DateMark())
            at = r.upperBound
        }
        mirror = mirror + Text(text[at...])
        return mirror.font(Theme.Typeface.bodyLarge).lineLimit(1).fixedSize().textRenderer(DateMarkRenderer())
    }
}

extension View {
    // As wide as the widest time in the column's font: a fixed width truncated or wrapped `오후 1:00`.
    // Verbatim: it is a measuring sample of the formatted time, never shown.
    func timeColumn() -> some View {
        ZStack(alignment: .leading) { Text(verbatim: "오후 12:00").hidden(); self }.lineLimit(1)
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
