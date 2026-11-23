import FolioActions
import FolioDomain
import SwiftUI

struct SessionsView: View {
    @Environment(\.linkFocus) private var focus
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
        let table = model.table(file)
        Page(anchor: model.anchor) {
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
                if !table.weeks.isEmpty {
                    Button(.sessionsTableToday) { model.showThisWeek(table) }.buttonStyle(.ghost)
                        .help(Text(.sessionsTableTodayHelp))
                }
                Button(.sessionsAdd, systemImage: "plus") { adding = true }.buttonStyle(.ghost)
                    .help(Text(.sessionsAddHelp))
            }

            if file.course.schedule.isEmpty { schedule }
            let left = model.leftUnwrapped(file)
            if !left.isEmpty { leftUnwrappedCard(left, file: file) }
            if !model.untouched.isEmpty { untouchedCard }

            // 자기 폭으로 표와 목록을 고른다. 창 크기가 아니라 칸의 폭을 따라야 좁은 칸에서도 넘치지 않는다. 재기 전에도 폭을 잴
            // 빈 뷰를 둔다. 비어 있는 Group에는 `onGeometryChange`가 붙지 않는다.
            Group {
                if !table.weeks.isEmpty {
                    switch model.form {
                    case .list: SessionAgendaView(model: model, course: course, table: table)
                    case .compact, .wide: SessionTableView(model: model, course: course, table: table)
                    case nil: Color.clear.frame(height: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                model.width = $0
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
        .onChange(of: focus, initial: true) { model.follow(focus, in: table) }
        .confirming($model.pending)
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
    @MainActor static let steps: [StepToggle<AttendanceState>.Option] = allCases.map {
        .init(value: $0, label: $0.label, tint: $0.tone.tint)
    }

    var label: String {
        switch self {
        case .present: String(localized: .attendancePresent)
        case .late: String(localized: .attendanceLate)
        case .absent: String(localized: .attendanceAbsent)
        case .excused: String(localized: .attendanceExcused)
        }
    }
}
