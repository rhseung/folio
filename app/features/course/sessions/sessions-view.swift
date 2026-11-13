import FolioActions
import FolioDomain
import SwiftUI

/// Sessions are made as classes happen. Each week lists its classes as cards: a saved session solid, a class only the
/// timetable knows of an empty dashed slot, and doing something to one (a 휴강, an absence) makes it a session. Anything
/// off the schedule is added by hand.
struct SessionsView: View {
    @Environment(\.accent) private var accent
    @State private var model: SessionsModel
    let course: LoadedCourse
    let openNote: (UUID) -> Void
    @State private var editingTimes = false
    @State private var adding = false

    init(workspace: Workspace, course: LoadedCourse, openNote: @escaping (UUID) -> Void) {
        _model = State(initialValue: SessionsModel(workspace: workspace, courseId: course.id))
        self.course = course
        self.openNote = openNote
    }

    var body: some View {
        let file = course.file
        Page {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(.sessionsTitle).font(Theme.Typeface.pageTitle)
                    (Text(model.subtitle(file)).foregroundStyle(Theme.Palette.textTertiary)
                     + (model.nextExam(file).map { Text(" · ").foregroundStyle(Theme.Palette.textTertiary) + Text($0).fontWeight(.semibold).foregroundStyle(Theme.Palette.danger) } ?? Text("")))
                }
                Spacer()
                Button(.sessionsAdd, systemImage: "plus") { adding = true }.buttonStyle(.ghost)
                    .help(Text(.sessionsAddHelp))
            }

            if file.course.schedule.isEmpty { schedule }
            let left = model.leftUnwrapped(file)
            if !left.isEmpty { leftUnwrappedCard(left, file: file) }
            if !model.untouched.isEmpty { untouchedCard }

            // Lazy, so a narrower or wider pane lays out only the cards in view: a term's weeks of cards laid out at
            // every width of a divider's drag kept it near 30 frames a second (#62). The headers and cards go in
            // flat, each its own item, so a link can scroll to a card no one has scrolled to yet (`linkTarget`).
            let weeks = model.weeks(file)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(weeks) { week in
                    header(week)
                        .padding(.top, week.id == weeks.first?.id ? 0 : Theme.Space.section)
                    ForEach(week.rows) { row in
                        self.row(row, file: file, top: row.id == week.rows.first?.id ? Theme.Space.s : Theme.Space.xs)
                    }
                }
            }
        }
        .sheet(isPresented: $editingTimes) { ClassTimesSheet(workspace: model.workspace, course: course) }
        .sheet(isPresented: $adding) { SessionSheet(workspace: model.workspace, request: SessionSheetRequest(course: course.id)) }
        .sheet(item: $model.wrapUpRun) { run in
            SessionSheet(workspace: model.workspace, request: SessionSheetRequest(course: course.id, session: run.current, asked: true),
                         step: model.step(of: run), saved: model.wrappedUpOne)
                // A new sheet model for each class: the one before's answers must not carry over.
                .id(run.current)
        }
        .task(id: file.sessions) { model.loadUntouched(course) }
        .confirming($model.pending)
    }

    func header(_ week: SessionsModel.Week) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(.sessionsWeek(week.number)).font(Theme.Typeface.sectionTitle)
                .foregroundStyle(week.thisWeek ? accent.ink : Theme.Palette.textSecondary)
                // The accent color is the only visible mark, so VoiceOver needs the word.
                .accessibilityValue(week.thisWeek ? String(localized: .sessionsThisWeek) : "")
            Text(week.range).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            if week.examWeek {
                Text("· " + String(localized: .sessionsExamWeek)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(minHeight: 24)
    }

    /// `top`: the room above it, inside the `.id` a link scrolls to.
    @ViewBuilder func row(_ row: SessionsModel.TimelineRow, file: CourseFile, top: CGFloat) -> some View {
        switch row.item {
        case .week, .month:
            EmptyView()
        case .exam(let exam, let date):
            ExamMarkerRow(model: model, exam: exam, date: date).padding(.top, top)
        case .session(let session, let exams):
            LiveTime(model.workspace) { now in
                SessionCard(model: model, course: course, session: session, now: now, openNote: openNote)
                    .modifier(ClassExamCard(model: model, exams: exams, now: now))
            }
            .linkTarget(session.id)
            .fileDrop { model.importFiles($0, into: session) }
            .padding(.top, top)
            // Outermost, where the lazy stack finds it before the card is built.
            .id(session.id)
        case .planned(_, let exams):
            if let item = row.planned {
                PlannedSessionCard(model: model, item: item, openNote: openNote, editTimes: { editingTimes = true })
                    .modifier(ClassExamCard(model: model, exams: exams, now: model.workspace.now))
                    .padding(.top, top)
            }
        }
    }

    /// Shown only while the course has no weekly times. They are a course property, edited with the rest of the
    /// course; here they only suggest sessions.
    var schedule: some View {
        Card {
            CardRow(last: true) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(.sessionsClassTimes)
                    Text(.sessionsClassTimesEmpty)
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer(minLength: Theme.Space.m)
                Button(.sessionsClassTimesAdd) { editingTimes = true }.buttonStyle(.ghost)
            }
            .contentShape(.rect)
            .contextMenu { Button(.sessionsClassTimesAddEllipsis) { editingTimes = true } }
        }
    }

    func leftUnwrappedCard(_ left: [Session], file: CourseFile) -> some View {
        let shown = Array(left.prefix(4))
        return NoticeCard(title: String(localized: .wrapUpLeftTitle(left.count)),
                          detail: String(localized: .wrapUpLeftDetail),
                          systemImage: "checklist") {
            Button(.wrapUpLeftGo) { model.startWrapUps(file) }.buttonStyle(.pointing(.bordered))
        } rows: {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && left.count == shown.count) {
                    Text(file.title(of: s, calendar: model.calendar)).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(model.gapsLine(model.leftGaps(s, in: file))).font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
            }
            if left.count > shown.count {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(left.count - shown.count))) }
            }
        }
    }

    /// Left over from when whole terms were made ahead; deleted only once the user agrees.
    var untouchedCard: some View {
        let shown = model.untouchedShown
        return NoticeCard(title: String(localized: .sessionsUntouchedTitle(model.untouched.count)),
                          detail: String(localized: .sessionsUntouchedDetail),
                          systemImage: "calendar.badge.minus") {
            Button(.sessionsRemoveEllipsis) { model.removeUntouched() }.buttonStyle(.pointing(.bordered))
        } rows: {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && model.untouchedMore == 0) {
                    Text(s.date.formatted(.dateTime.month().day().weekday().hour().minute())).monospacedDigit()
                    Spacer()
                }
            }
            if model.untouchedMore > 0 {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(model.untouchedMore))) }
            }
        }
    }
}

extension AttendanceState {
    @MainActor static let steps: [StepToggle<AttendanceState>.Option] = [
        .init(value: .present, label: String(localized: .attendancePresent), tint: Theme.Palette.success),
        .init(value: .late, label: String(localized: .attendanceLate), tint: Theme.Palette.warning),
        .init(value: .absent, label: String(localized: .attendanceAbsent), tint: Theme.Palette.danger),
        .init(value: .excused, label: String(localized: .attendanceExcused), tint: Theme.Palette.textSecondary),
    ]

    var label: String {
        switch self {
        case .present: String(localized: .attendancePresent)
        case .late: String(localized: .attendanceLate)
        case .absent: String(localized: .attendanceAbsent)
        case .excused: String(localized: .attendanceExcused)
        }
    }
}
