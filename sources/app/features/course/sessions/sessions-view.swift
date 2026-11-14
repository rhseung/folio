import FolioActions
import FolioDomain
import SwiftUI

struct SessionsView: View {
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink
    @State private var model: SessionsModel
    let course: LoadedCourse
    @State private var editingTimes = false
    @State private var adding = false

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: SessionsModel(workspace: workspace, courseId: course.id))
        self.course = course
    }

    var body: some View {
        let file = course.file
        Page {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(.sessionsTitle).font(Theme.Typeface.pageTitle)
                    (Text(model.subtitle(file)).foregroundStyle(Theme.Palette.textTertiary)
                        + (model.nextExam(file).map {
                            Text(" · ").foregroundStyle(Theme.Palette.textTertiary)
                                + Text($0).fontWeight(.semibold).foregroundStyle(Theme.Palette.danger)
                        } ?? Text("")))
                }
                Spacer()
                Button(.sessionsAdd, systemImage: "plus") { adding = true }.buttonStyle(.ghost)
                    .help(Text(.sessionsAddHelp))
            }

            if file.course.schedule.isEmpty { schedule }
            let left = model.leftUnwrapped(file)
            if !left.isEmpty { leftUnwrappedCard(left, file: file) }
            if !model.untouched.isEmpty { untouchedCard }

            // Lazy로 두어 칸 폭이 바뀔 때 보이는 카드만 배치한다. 구분선을 끄는 동안 폭마다 한 학기의 카드를 모두
            // 배치하면 초당 30프레임 근처에 머물렀다. 머리와 카드는 각각 항목으로 평평하게 넣어야, 아직 스크롤하지 않은
            // 카드로도 링크가 스크롤할 수 있다(`linkTarget`).
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
            SessionSheet(
                workspace: model.workspace, request: SessionSheetRequest(course: course.id, session: run.current, asked: true),
                step: model.step(of: run), saved: model.wrappedUpOne
            )
            // 이전 수업의 답이 넘어오면 안 되므로 수업마다 시트 모델을 새로 만든다.
            .id(run.current)
        }
        .task(id: file.sessions) { model.loadUntouched(course) }
        .confirming($model.pending)
    }

    func header(_ week: SessionsModel.Week) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(.sessionsWeek(week.number)).font(Theme.Typeface.sectionTitle)
                .foregroundStyle(week.thisWeek ? accent.ink : Theme.Palette.textSecondary)
                // 강조색만 눈에 보이는 표시라서 VoiceOver에는 낱말이 필요하다.
                .accessibilityValue(week.thisWeek ? String(localized: .sessionsThisWeek) : "")
            Text(week.range).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            if week.examWeek {
                Text("· " + String(localized: .sessionsExamWeek)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(minHeight: 24)
    }

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
            // lazy stack이 카드를 만들기 전에 찾을 수 있도록 가장 바깥에 둔다.
            .id(session.id)
        case .planned(_, let exams):
            if let item = row.planned {
                PlannedSessionCard(model: model, item: item, openNote: openNote, editTimes: { editingTimes = true })
                    .modifier(ClassExamCard(model: model, exams: exams, now: model.workspace.now))
                    .padding(.top, top)
            }
        }
    }

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

    func openNote(_ id: UUID) {
        openLink(AppLink(.note, id), course: course.id)
    }

    func leftUnwrappedCard(_ left: [Session], file: CourseFile) -> some View {
        let shown = Array(left.prefix(4))
        return NoticeCard(
            title: String(localized: .wrapUpLeftTitle(left.count)),
            detail: String(localized: .wrapUpLeftDetail),
            systemImage: "checklist"
        ) {
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

    var untouchedCard: some View {
        let shown = model.untouchedShown
        return NoticeCard(
            title: String(localized: .sessionsUntouchedTitle(model.untouched.count)),
            detail: String(localized: .sessionsUntouchedDetail),
            systemImage: "calendar.badge.minus"
        ) {
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
