import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct TodayView: View {
    @State private var model: TodayModel
    @Environment(\.searchTarget) private var searchTarget
    @State private var skippingAll = false
    @State private var wide = true

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
        return Page {
            PageHeader(title: model.heading(summary, now: now), subtitle: model.workspace.currentSemester?.title)

            // One slot for both: an empty NowClassCard still took a stack slot and left a double gap above the field.
            VStack(alignment: .leading, spacing: 0) {
                NowClassCard(model: model)
                QuickAddField(workspace: model.workspace)
            }

            if !summary.exams.isEmpty {
                let exams = summary.exams
                // Five side by side and the rest a scroll away: an exam week brings about five at once. Fewer share the
                // row's width, so two exams fill it instead of huddling at its start.
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(exams, id: \.exam.id) {
                            examCard($0, stacked: exams.count > 2)
                                .containerRelativeFrame(.horizontal, count: min(exams.count, 5), spacing: Theme.Space.m)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .overflowFade(.horizontal)
            }

            AttendanceWarnings(model: model)

            // Deadlines get a side column so they sit beside the day's work: in a grid row with the classes, an empty
            // class list left a hole as tall as the deadline timeline. Narrow, they stack above the long review queue.
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                if wide {
                    HStack(alignment: .top, spacing: Theme.Space.xl) {
                        VStack(alignment: .leading, spacing: Theme.Space.section) {
                            classesBlock(summary, now: now)
                            ExamPlanTodayBlock(courses: model.current)
                            reviewBlock(reviews, notes: summary.missingReviewNotes)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        deadlinesBlock(summary).frame(width: Self.sideColumn)
                    }
                } else {
                    classesBlock(summary, now: now)
                    ExamPlanTodayBlock(courses: model.current)
                    deadlinesBlock(summary)
                    reviewBlock(reviews, notes: summary.missingReviewNotes)
                }
            }
            // Below this the main column gets too narrow for a unit title beside its overdue chip.
            .onGeometryChange(for: Bool.self) { $0.size.width >= Self.sideColumn + 440 } action: { wide = $0 }

            StudyTimeBlock(workspace: model.workspace)
        }
        .navigationSubtitle(summary.studyDay.description)
    }

    private static let sideColumn: CGFloat = 320

    func examCard(_ item: TodaySummary.ExamItem, stacked: Bool) -> some View {
        // Paper card with the course as an icon: an accent tint as the whole background sank into the page in dark mode.
        // A fifth of the row is too narrow for title and D-day on one line, so three or more cards stack theirs.
        Card(padding: Theme.Space.l) {
            if stacked {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Theme.Space.tight) {
                        CourseMark(model.workspace, item.courseId, inline: true)
                        Text(model.title(item.courseId)).lineLimit(1)
                    }
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                    Text(item.exam.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                        .padding(.top, Theme.Space.tight)
                    Text(model.dDay(item)).font(Theme.Typeface.figureCompact).monospacedDigit().foregroundStyle(DdayChip.heat(item.dDay))
                        .padding(.top, Theme.Space.xs)
                    Text(model.examStart(item)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        .padding(.top, Theme.Space.xxs)
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.tight) {
                            CourseMark(model.workspace, item.courseId, inline: true)
                            Text(model.examTitle(item)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                        }
                        Text(model.examStart(item)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(model.dDay(item)).font(Theme.Typeface.figureCompact).monospacedDigit().foregroundStyle(DdayChip.heat(item.dDay)).fixedSize()
                }
            }
        }
        .opens { go(item.courseId, .exams) }
        .contextMenu { Button(.commonShowExams, systemImage: "calendar.badge.exclamationmark") { go(item.courseId, .exams) } }
    }

    /// A class's review note comes first, then the units: writing the note is the day's review of that class
    /// (docs/SPEC.md "복습 스케줄러"), and a unit linked to it waits on the note anyway.
    func reviewBlock(_ reviews: TodayModel.Reviews, notes: [TodaySummary.SessionItem]) -> some View {
        let queue = reviews.queue, deferred = reviews.deferred, all = reviews.all
        return Block(title: String(localized: .todayReviews), note: queue.isEmpty ? nil : String(localized: .todayReviewsNote), trailing: {
            if !all.isEmpty {
                Button(.todayReviewsSkipAll) { skippingAll = true }
                    .buttonStyle(.ghost)
                    .confirmationDialog(String(localized: .todayReviewsSkipAllConfirm(all.count)), isPresented: $skippingAll) {
                        Button(.todayReviewsSkipAllButton(all.count)) { model.skip(all) }
                    } message: {
                        Text(.todayReviewsSkipAllMessage)
                    }
            }
        }) {
            Card {
                // A day with nothing scheduled has no progress to show; a full "0 / 0" banner reads as a bug.
                if reviews.doneToday + queue.count > 0 {
                    ReviewProgressBanner(done: reviews.doneToday, left: queue.count, streak: reviews.streak)
                } else if notes.isEmpty {
                    CardRow(last: true) { EmptyLine(String(localized: .todayReviewsEmpty)) }
                }
                noteRows(notes, limit: 6, endsCard: queue.isEmpty, widest: queue.count)
                ForEach(Array(queue.enumerated()), id: \.element.item.unitId) { i, entry in
                    ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId, then: queue[(i + 1)...].map { .init(courseId: $0.courseId, unitId: $0.item.unitId) }) { CardRow(last: i == queue.count - 1) {
                        reviewLead(widest: queue.count) { Text("\(i + 1)").foregroundStyle(Theme.Palette.textTertiary) }
                        CourseMark(model.workspace, entry.courseId)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(entry.unitTitle).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(model.reviewSubtitle(entry))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        if entry.item.overdueDays > 0 { Chip(String(localized: .todayReviewsOverdue(entry.item.overdueDays)), tone: .danger) }
                    } }
                    .contextMenu { reviewMenu(entry) }
                }
            }
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
    }

    func deadlinesBlock(_ summary: TodaySummary) -> some View {
        Block(String(localized: .todayDeadlines), note: summary.deadlines.isEmpty ? nil : String(localized: .todayDeadlinesCount(summary.deadlines.count))) {
            Card(padding: summary.deadlines.isEmpty ? 0 : Theme.Space.m) {
                if summary.deadlines.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .todayDeadlinesEmpty)) } }
                let days = model.deadlineDays(summary.deadlines, studyDay: summary.studyDay)
                ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                    deadlineDay(day, first: i == 0, last: i == days.count - 1)
                }
            }
        }
        .sheet(item: $model.editing) { AssignmentSheet(workspace: model.workspace, course: $0.course, assignment: $0.assignment) }
    }

    private static let pillHeight: CGFloat = 40

    func deadlineDay(_ day: TodayModel.DeadlineDay, first: Bool, last: Bool) -> some View {
        // Pill gaps live inside each day, so the rail runs unbroken from one day's node to the next.
        let inset = Theme.Space.tight / 2, node = inset + Self.pillHeight / 2
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(day.day).font(Theme.Typeface.figureMedium).monospacedDigit()
                    .foregroundStyle(day.isToday ? Theme.Palette.danger : Theme.Palette.text)
                Text(day.label).font(Theme.Typeface.label)
                    .foregroundStyle(day.isToday ? Theme.Palette.danger : Theme.Palette.textTertiary)
            }
            .frame(width: 40, height: Self.pillHeight, alignment: .trailing)
            .padding(.top, inset)
            ZStack(alignment: .top) {
                Rectangle().fill(Theme.Palette.line).frame(width: 1)
                    .padding(.top, first ? node : 0)
                    .frame(maxHeight: last ? node : .infinity, alignment: .top)
                CourseDot(color: day.isToday ? Theme.Palette.danger : Theme.Palette.lineStrong)
                    .padding(.top, node - Theme.Size.dot / 2)
            }
            .frame(width: Theme.Size.dot)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(spacing: Theme.Space.tight) {
                ForEach(day.items, id: \.assignment.id) { deadlinePill($0) }
            }
            .padding(.vertical, inset)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func deadlinePill(_ item: TodaySummary.DeadlineItem) -> some View {
        let accent = model.workspace.accent(item.courseId)
        return Button { model.edit(item) } label: {
            HStack(spacing: Theme.Space.s) {
                AssignmentStatusIcon(status: item.assignment.status, tint: accent.color)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(item.assignment.title).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink).lineLimit(1).layoutPriority(1)
                    Text(model.title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(accent.ink.secondary).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                if item.isToday {
                    Text(model.due(item)).font(Theme.Typeface.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.Palette.danger).fixedSize()
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Self.pillHeight)
            .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu {
            Button(.commonEditEllipsis) { model.edit(item) }
            Button(.todayDeadlinesShow, systemImage: "checklist") { go(item.courseId, .assignments) }
        }
    }

    func classesBlock(_ summary: TodaySummary, now: Date) -> some View {
        Block(String(localized: .todayClasses)) {
            let suggested = model.suggested(now: now, on: summary.studyDay)
            if !summary.classesToday.isEmpty || suggested.isEmpty {
                Card {
                    if summary.classesToday.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .todayClassesEmpty)) } }
                    ForEach(Array(summary.classesToday.enumerated()), id: \.element.session.id) { i, item in
                        classRow(item, last: i == summary.classesToday.count - 1)
                    }
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.card))
            }
            ForEach(suggested) { SuggestedSessionRow(item: $0, showsCourse: true, openNote: openNote(in: $0.courseId)) }
        }
    }

    func classRow(_ item: TodaySummary.SessionItem, last: Bool) -> some View {
        let start = item.session.date
        let end = model.end(of: item)
        let accent = model.workspace.accent(item.courseId)
        return Button { go(item.courseId, .sessions) } label: { TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = model.workspace.now
            let ongoing = end.map { now >= start && now < $0 } ?? false
            let ended = !ongoing && now >= (end ?? start)
            CardRow(last: last) {
                // On a full day most rows are already over; greyed, they let the classes still ahead stand out.
                Group {
                    Text(start.formatted(date: .omitted, time: .shortened)).timeColumn().font(Theme.Typeface.caption).monospacedDigit()
                    CourseMark(model.workspace, item.courseId)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(model.title(item.courseId)).lineLimit(1)
                        Text(model.sessionName(item.courseId, item.session)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .opacity(ended ? 0.45 : 1)
                Spacer()
                if ongoing {
                    Text(.todayClassesNow).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                } else if ended {
                    Text(.commonEnded).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            // Progress and minutes stay on the 지금 수업 card above, so the row only marks which class it is.
            .background(ongoing ? accent.tint : .clear)
            .contentShape(.rect)
        } }
        .buttonStyle(.pointing(.plain))
        .contextMenu { SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId)) { go(item.courseId, .sessions) } }
    }

    @ViewBuilder func reviewMenu(_ entry: Workspace.ReviewEntry) -> some View {
        Button(.todayReviewsShowUnits, systemImage: "list.bullet") { go(entry.courseId, .units) }
        Button(.todayReviewsSkip, systemImage: "forward") { model.skip([entry]) }
    }

    // Note rows keep the unit rows' number column, empty, so every course icon in the card lines up.
    func reviewLead(widest: Int, @ViewBuilder mark: () -> some View) -> some View {
        Text("\(widest)").hidden()
            .overlay(alignment: .trailing, content: mark)
            .font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
    }

    @ViewBuilder func noteRows(_ items: [TodaySummary.SessionItem], limit: Int, endsCard: Bool, widest: Int) -> some View {
        let (shown, more) = model.noteRows(items, limit: limit)
        ForEach(Array(shown.enumerated()), id: \.element.session.id) { i, item in
            CardRow(last: endsCard && more == 0 && i == shown.count - 1) {
                // The checkmark stays outside: a button inside another button's label never gets the click.
                Button {
                    if let id = model.reviewNote(of: item) { openNote(in: item.courseId)(id) }
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        if widest > 0 { reviewLead(widest: widest) { EmptyView() } }
                        CourseMark(model.workspace, item.courseId)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(model.noteTitle(item)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(model.noteSubtitle(item))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .help(Text(item.session.reviewNoteUnfinished ? .todayNoteOpenHelp : .todayNoteCreateHelp))
                // A note made from the template isn't written yet, so the checkmark finishes it; without a note it skips the session.
                if item.session.reviewNoteUnfinished {
                    Button { model.finishReviewNote(item) } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(.ghost)
                        .help(Text(.todayNoteFinish))
                        .accessibilityLabel(Text(.todayNoteFinish))
                } else {
                    Button { model.skipReviewNote(item) } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(.ghost)
                        .help(Text(.todayNoteNoReviewHelp))
                        .accessibilityLabel(Text(.todayNoteNoReview))
                }
            }
            .contextMenu {
                SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId)) { go(item.courseId, .sessions) }
                Divider()
                Button(.todayNoteNoReview, systemImage: "forward") { model.skipReviewNote(item) }
            }
        }
        if more > 0 {
            CardRow(last: endsCard) { EmptyLine(String(localized: .todayNoteMore(more))) }
        }
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
    @Environment(\.searchTarget) private var searchTarget

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = model.workspace.now
            if let item = model.nowClass(at: now) {
                card(courseId: item.courseId, name: item.name, room: item.room, start: item.start, end: item.end, now: now) {
                    if let suggested = item.suggested {
                        SuggestedSessionActions(item: suggested) { searchTarget.wrappedValue = SearchTarget(courseId: suggested.courseId, section: .notes, noteId: $0) }
                    }
                }
            }
        }
    }

    func card(courseId: UUID, name: String, room: String, start: Date, end: Date, now: Date, @ViewBuilder actions: () -> some View) -> some View {
        let accent = model.workspace.accent(courseId)
        let fraction = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
        return HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(room.isEmpty ? .todayNowClass : .todayNowClassRoom(room)).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                Text("\(model.title(courseId)) · \(name)").font(Theme.Typeface.figureCompact).lineLimit(1)
                Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
            }
            Spacer(minLength: Theme.Space.m)
            actions()
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(.todayNowClassMinutes(Int(end.timeIntervalSince(now) / 60) + 1)).font(Theme.Typeface.figure).foregroundStyle(accent.ink)
                Text(.todayNowClassLeft).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(Theme.Inset.stat)
        .background(alignment: .bottomLeading) {
            // A partial tint read as a broken card in light mode; progress is a bar along the bottom instead.
            GeometryReader { proxy in accent.color.frame(width: proxy.size.width * fraction, height: 4).frame(maxHeight: .infinity, alignment: .bottom) }
        }
        .background(accent.tint)
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

struct ReviewProgressBanner: View {
    let done: Int
    let left: Int
    let streak: Int

    var body: some View {
        let total = done + left
        let fraction = total == 0 ? 1 : Double(done) / Double(total)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text("\(done)").font(Theme.Typeface.figureCompact).rolling("\(done)")
            Text(.todayProgressTotal(total)).font(Theme.Typeface.bodyStrong).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Space.m)
            Text(left == 0 ? .todayProgressDone : .todayProgressLeft(left)).font(Theme.Typeface.caption).monospacedDigit()
                .foregroundStyle(left == 0 ? Theme.Palette.success : Theme.Palette.textSecondary)
            if streak > 0 {
                Label(.todayProgressStreak(streak), systemImage: "flame.fill").labelStyle(.titleAndIcon)
                    .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.Palette.warning)
                    .symbolEffect(.bounce, value: streak)
                    .padding(.leading, Theme.Space.s)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Theme.Palette.fill
                    LinearGradient(colors: [Theme.Palette.success.opacity(0.08), Theme.Palette.success.opacity(0.32)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * fraction)
                        .overlay(alignment: .trailing) {
                            if fraction > 0 && fraction < 1 { Theme.Palette.success.frame(width: 2) }
                        }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .animation(.spring(duration: 0.6, bounce: 0.2), value: fraction)
        }
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
