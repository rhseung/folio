import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct TodayView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.searchTarget) private var searchTarget
    @State private var skippingAll = false

    var current: [LoadedCourse] {
        workspace.currentCourses
    }

    var body: some View {
        // Redrawn at each day boundary, so a page left open overnight turns to the new study day.
        TimelineView(.periodic(from: nextDayStart, by: 86_400)) { _ in page(now: .now) }
            .navigationTitle("오늘")
    }

    var nextDayStart: Date {
        let calendar = workspace.calendar
        let start = workspace.today.date(in: calendar).flatMap { calendar.date(byAdding: .minute, value: workspace.settings.dayBoundaryMinutes, to: $0) }
        return start.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
    }

    func page(now: Date) -> some View {
        let summary = TodaySummary.build(courses: current.map(\.file), now: now, settings: workspace.settings, calendar: workspace.calendar)
        let queue = workspace.reviewQueue(now: now)
        let todayQueue = queue.filter { $0.item.deferred == nil }
        let deferred = queue.filter { $0.item.deferred != nil }
        // Narrower than other pages: a glance at today, not a table to read across.
        return Page(maxWidth: 780) {
            // The study day, not the calendar date: until the day boundary the classes and reviews below are still
            // the previous day's, and a title saying otherwise contradicts them.
            PageHeader(title: (summary.studyDay.date(in: workspace.calendar) ?? now).formatted(.dateTime.month().day().weekday(.wide)),
                       subtitle: workspace.currentSemester?.title)

            // One slot for both: an empty NowClassCard still took a stack slot and left a double gap above the field.
            VStack(alignment: .leading, spacing: 0) {
                NowClassCard()
                QuickAddField()
            }

            if !summary.exams.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Theme.Space.m - 2)], spacing: Theme.Space.m - 2) {
                    ForEach(summary.exams, id: \.exam.id) { item in
                        let accent = workspace.accent(item.courseId)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("\(title(item.courseId)) · \(item.exam.title)").font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink).lineLimit(1)
                            Text(item.dDay == 0 ? "D-day" : "D-\(item.dDay)").font(Theme.Typeface.figureCompact).foregroundStyle(DdayChip.heat(item.dDay))
                            Text(item.exam.start?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? "").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.horizontal, Theme.Inset.panel)
                        .padding(.vertical, Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.card))
                        .opens { go(item.courseId, .exams) }
                        .contextMenu { Button("시험 보기", systemImage: "calendar.badge.exclamationmark") { go(item.courseId, .exams) } }
                    }
                }
            }

            ExamPlanTodayBlock(courses: current)
            AttendanceWarnings()

            // Classes and deadlines are short lists of equal weight, side by side when there's room for their titles.
            // The review queue can run to dozens of rows, so it gets the full width below them instead of a column
            // that pushes everything else down.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.Space.xl, alignment: .top)], alignment: .leading, spacing: Theme.Space.xl) {
                classesBlock(summary, now: now)
                deadlinesBlock(summary)
            }
            reviewBlock(todayQueue, deferred: deferred, notes: summary.missingReviewNotes)

            StudyTimeBlock()
        }
        .navigationSubtitle(summary.studyDay.description)
    }

    /// A class's review note comes first, then the units: writing the note is the day's review of that class
    /// (docs/SPEC.md "복습 스케줄러"), and a unit linked to it waits on the note anyway.
    func reviewBlock(_ queue: [Workspace.ReviewEntry], deferred: [Workspace.ReviewEntry], notes: [TodaySummary.SessionItem]) -> some View {
        let all = queue + deferred
        let progress = workspace.reviewProgress(now: .now)
        return Block(title: "오늘 복습", note: queue.isEmpty ? nil : "우선순위 순", trailing: {
            if !all.isEmpty {
                Button("모두 건너뛰기") { skippingAll = true }
                    .buttonStyle(.ghost)
                    .confirmationDialog("복습 \(all.count)단원을 건너뛸까요?", isPresented: $skippingAll) {
                        Button("\(all.count)단원 건너뛰기") { workspace.skipReviews(all.map { ($0.courseId, $0.item.unitId) }) }
                    } message: {
                        Text("이미 공부한 것으로 보고 오늘 화면에서 뺍니다. 틀린 퀴즈 카드나 시험 계획이 생기면 다시 올라옵니다.")
                    }
            }
        }) {
            Card {
                // A day with nothing scheduled has no progress to show; a full "0 / 0" banner reads as a bug.
                if progress.doneToday + queue.count > 0 {
                    ReviewProgressBanner(done: progress.doneToday, left: queue.count, streak: progress.streak)
                } else if notes.isEmpty {
                    CardRow(last: true) { EmptyLine("오늘 복습할 것이 없습니다") }
                }
                noteRows(notes, limit: 6, endsCard: queue.isEmpty)
                ForEach(Array(queue.enumerated()), id: \.element.item.unitId) { i, entry in
                    ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId, then: queue[(i + 1)...].map { .init(courseId: $0.courseId, unitId: $0.item.unitId) }) { CardRow(last: i == queue.count - 1) {
                        // The widest number, hidden, sizes the column so every row lines up however long the queue is.
                        Text("\(queue.count)").hidden()
                            .overlay(alignment: .trailing) { Text("\(i + 1)") }
                            .font(Theme.Typeface.caption).monospacedDigit().lineLimit(1).foregroundStyle(Theme.Palette.textTertiary)
                        CourseDot(color: workspace.accent(entry.courseId).color)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(entry.unitTitle).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(entry.item.writeNoteFirst ? "\(title(entry.courseId)) · 복습 노트 작성부터" : title(entry.courseId))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        if entry.item.overdueDays > 0 { Chip("\(entry.item.overdueDays)일 밀림", tone: .danger) }
                    } }
                    .contextMenu { reviewMenu(entry) }
                }
            }
            if !deferred.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("하루 상한을 넘어 내일로 미룸").font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textSecondary)
                    ForEach(deferred, id: \.item.unitId) { entry in
                        ReviewOpener(courseId: entry.courseId, unitId: entry.item.unitId) { HStack(spacing: Theme.Space.m) {
                            CourseDot(color: workspace.accent(entry.courseId).color)
                            Text(entry.unitTitle)
                            Spacer()
                            Text(title(entry.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
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
        Block("마감", note: summary.deadlines.isEmpty ? nil : "\(summary.deadlines.count)개") {
            Card {
                if summary.deadlines.isEmpty { CardRow(last: true) { EmptyLine("남은 마감이 없습니다") } }
                ForEach(Array(summary.deadlines.enumerated()), id: \.element.assignment.id) { i, item in
                    Button { go(item.courseId, .assignments) } label: { CardRow(last: i == summary.deadlines.count - 1) {
                        CourseDot(color: workspace.accent(item.courseId).color)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(item.assignment.title).lineLimit(1)
                            Text(title(item.courseId)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                        Text(item.isToday ? item.assignment.due!.formatted(date: .omitted, time: .shortened) : item.assignment.due!.formatted(.dateTime.month().day().weekday()))
                            .font(Theme.Typeface.caption.weight(item.isToday ? .bold : .regular)).monospacedDigit()
                            .foregroundStyle(item.isToday ? Theme.Palette.danger : Theme.Palette.textSecondary)
                            .fixedSize()
                    }.contentShape(.rect) }
                    .buttonStyle(.pointing(.plain))
                    .contextMenu { Button("과제 보기", systemImage: "checklist") { go(item.courseId, .assignments) } }
                }
            }
        }
    }

    func classesBlock(_ summary: TodaySummary, now: Date) -> some View {
        Block("오늘 수업") {
            let suggested = workspace.suggestedSessions(now: now).filter {
                workspace.settings.studyDay(of: $0.suggestion.date, calendar: workspace.calendar) == summary.studyDay
            }
            if !summary.classesToday.isEmpty || suggested.isEmpty {
                Card {
                    if summary.classesToday.isEmpty { CardRow(last: true) { EmptyLine("오늘은 수업이 없습니다") } }
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
        let end = item.session.end(schedule: workspace.course(item.courseId)?.file.course.schedule ?? [], calendar: workspace.calendar)
        let accent = workspace.accent(item.courseId)
        return Button { go(item.courseId, .sessions) } label: { TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let ongoing = end.map { now >= start && now < $0 } ?? false
            CardRow(last: last) {
                Text(start.formatted(date: .omitted, time: .shortened)).timeColumn().font(Theme.Typeface.caption).monospacedDigit()
                CourseDot(color: accent.color)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title(item.courseId)).lineLimit(1)
                    Text(sessionName(item.courseId, item.session)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if ongoing {
                    Text("지금").font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                } else if now >= (end ?? start) {
                    Text("끝남").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
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
        Button("단원 보기", systemImage: "list.bullet") { go(entry.courseId, .units) }
        Button("오늘 복습 건너뛰기", systemImage: "forward") { workspace.skipReviews([(entry.courseId, entry.item.unitId)]) }
    }

    @ViewBuilder func noteRows(_ items: [TodaySummary.SessionItem], limit: Int, endsCard: Bool) -> some View {
        let shown = Array(items.suffix(limit).reversed())
        let more = items.count - shown.count
        ForEach(Array(shown.enumerated()), id: \.element.session.id) { i, item in
            CardRow(last: endsCard && more == 0 && i == shown.count - 1) {
                // The checkmark stays outside: a button inside another button's label never gets the click.
                Button {
                    if let id = workspace.note(.review, of: item.session.id, in: item.courseId) { openNote(in: item.courseId)(id) }
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: "square.and.pencil").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
                        CourseDot(color: workspace.accent(item.courseId).color)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text("\(title(item.courseId)) · \(sessionName(item.courseId, item.session))").font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text((item.session.reviewNoteUnfinished ? "복습 노트 마저 쓰기 · " : "복습 노트 쓰기 · ") + item.session.date.formatted(.dateTime.month().day().weekday()))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .help(item.session.reviewNoteUnfinished ? "복습 노트를 엽니다" : "복습 노트를 만들어 엽니다")
                // A note made from the template isn't written yet, so the checkmark finishes it; without a note it skips the session.
                if item.session.reviewNoteUnfinished {
                    Button { workspace.setReviewNoteUnfinished(false, of: item.session.id, in: item.courseId) } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(.ghost)
                        .help("복습 노트 작성 완료")
                        .accessibilityLabel("복습 노트 작성 완료")
                } else {
                    Button { workspace.setSkipsReview(true, of: item.session.id, in: item.courseId) } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(.ghost)
                        .help("복습 필요 없음: 진도 없이 채점만 한 날처럼 복습할 것이 없는 회차")
                        .accessibilityLabel("복습 필요 없음")
                }
            }
            .contextMenu {
                SessionMenu(courseId: item.courseId, sessionId: item.session.id, openNote: openNote(in: item.courseId)) { go(item.courseId, .sessions) }
                Divider()
                Button("복습 필요 없음", systemImage: "forward") { workspace.setSkipsReview(true, of: item.session.id, in: item.courseId) }
            }
        }
        if more > 0 {
            CardRow(last: endsCard) { EmptyLine("복습 노트 없는 회차 외 \(more)개") }
        }
    }

    func title(_ id: UUID) -> String {
        workspace.course(id)?.title ?? ""
    }

    func go(_ course: UUID, _ section: CourseSection) {
        searchTarget.wrappedValue = SearchTarget(courseId: course, section: section)
    }

    func openNote(in course: UUID) -> (UUID) -> Void {
        { searchTarget.wrappedValue = SearchTarget(courseId: course, section: .notes, noteId: $0) }
    }

    func sessionName(_ course: UUID, _ session: Session) -> String {
        workspace.course(course)?.file.name(of: session) ?? ""
    }
}

struct NowClassCard: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.searchTarget) private var searchTarget

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            if let item = workspace.ongoingClass(at: now), let course = workspace.course(item.courseId) {
                let room = course.file.course.schedule.first { $0.weekday == workspace.calendar.isoWeekday(of: item.session.date) }?.room ?? ""
                card(courseId: item.courseId, name: course.file.name(of: item.session), room: room, start: item.session.date, end: item.end, now: now) { EmptyView() }
            } else if let item = workspace.suggestedSessions(now: now).first(where: { $0.suggestion.date <= now }) {
                // Under way but not made yet: the card offers what starting the class needs.
                card(courseId: item.courseId, name: item.name, room: item.suggestion.room, start: item.suggestion.date, end: item.suggestion.end, now: now) {
                    SuggestedSessionActions(item: item) { searchTarget.wrappedValue = SearchTarget(courseId: item.courseId, section: .notes, noteId: $0) }
                }
            }
        }
    }

    func card(courseId: UUID, name: String, room: String, start: Date, end: Date, now: Date, @ViewBuilder actions: () -> some View) -> some View {
        let accent = workspace.accent(courseId)
        let fraction = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
        return HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("지금 수업" + (room.isEmpty ? "" : " · \(room)")).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                Text("\(workspace.course(courseId)?.title ?? "") · \(name)").font(Theme.Typeface.figureCompact).lineLimit(1)
                Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
            }
            Spacer(minLength: Theme.Space.m)
            actions()
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text("\(Int(end.timeIntervalSince(now) / 60) + 1)분").font(Theme.Typeface.figure).foregroundStyle(accent.ink)
                Text("남음").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
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
    @Environment(Workspace.self) private var workspace
    var fixedCourse: UUID?
    @State private var text = ""

    func parse(_ line: String) -> QuickAdd? {
        let courses = workspace.currentCourses.map(\.file.course)
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : QuickAdd.parse(line, courses: courses, codes: workspace.catalog.codes, fixedCourse: fixedCourse, now: .now, calendar: workspace.calendar)
    }

    var body: some View {
        let parsed = parse(text)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary)
                TextField("빠른 추가: 선대 HW5 금 23:59", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Typeface.bodyLarge)
                    // The marks are drawn behind the field instead of styling its text: rewriting the text while
                    // typing breaks Korean composition and eats characters.
                    .background(alignment: .leading) { marks(parsed?.dueRanges ?? []).allowsHitTesting(false) }
                    .onSubmit { if let parsed { save(parsed) } }
                if let parsed {
                    Button("저장") { save(parsed) }
                        .buttonStyle(.pointing(.glassProminent))
                        .disabled(parsed.courseId == nil || parsed.title.isEmpty)
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
        let due = parsed.due?.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).hour().minute())
        return HStack(spacing: Theme.Space.tight) {
            if let id = parsed.courseId, let course = workspace.course(id) {
                CourseDot(color: workspace.accent(id).color, size: 8)
                Text(course.title).foregroundStyle(Theme.Palette.textSecondary)
            } else {
                Text("과목을 찾지 못함").foregroundStyle(Theme.Palette.danger)
            }
            if let due { Text("· \(due)").foregroundStyle(Theme.Palette.textTertiary) }
            if parsed.repeats == .weekly { Label("매주", systemImage: "repeat").foregroundStyle(Theme.Palette.textTertiary) }
            if !parsed.title.isEmpty { Text("· \(parsed.title)").foregroundStyle(Theme.Palette.textTertiary) }
        }
        .font(Theme.Typeface.caption).lineLimit(1)
    }

    /// The line laid out again under the field, invisible, so `DateMarkRenderer` can draw a pill behind the deadline words.
    func marks(_ ranges: [Range<String.Index>]) -> some View {
        var mirror = Text("")
        var at = text.startIndex
        for r in ranges {
            mirror = mirror + Text(text[at..<r.lowerBound]) + Text(text[r]).customAttribute(DateMark())
            at = r.upperBound
        }
        mirror = mirror + Text(text[at...])
        return mirror.font(Theme.Typeface.bodyLarge).lineLimit(1).fixedSize().textRenderer(DateMarkRenderer())
    }

    func save(_ parsed: QuickAdd) {
        guard let id = parsed.courseId, !parsed.title.isEmpty else { return }
        guard workspace.run(AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats)) != nil else { return }
        text = ""
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
            Text("/ \(total)단원").font(Theme.Typeface.bodyStrong).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Space.m)
            Text(left == 0 ? "오늘 복습 끝" : "\(left)단원 남음").font(Theme.Typeface.caption).monospacedDigit()
                .foregroundStyle(left == 0 ? Theme.Palette.success : Theme.Palette.textSecondary)
            if streak > 0 {
                Label("\(streak)일 연속", systemImage: "flame.fill").labelStyle(.titleAndIcon)
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
    func timeColumn() -> some View {
        ZStack(alignment: .leading) { Text(verbatim: "오후 12:00").hidden(); self }.lineLimit(1)
    }
}
