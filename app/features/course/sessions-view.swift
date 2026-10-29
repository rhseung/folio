import FolioActions
import FolioDomain
import SwiftUI

/// Sessions grouped by week and split at the midterm and the final. Sessions are made as classes happen: the weekly
/// schedule only suggests the next lecture, and the rest are added by hand (docs/SPEC.md "강의 회차").
struct SessionsView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let openNote: (UUID) -> Void
    @State private var editingTimes = false
    @State private var adding = false
    @State private var untouched: [Session] = []
    @State private var confirmingDelete = false

    var body: some View {
        let file = course.file
        let weeks = Dictionary(grouping: file.sessions, by: \.week).sorted { $0.key < $1.key }.map { $0.value.sorted { $0.date < $1.date } }
        let exams = file.exams.filter { $0.kind == .midterm || $0.kind == .final }
            .compactMap { e in e.start.map { (exam: e, date: $0) } }.sorted { $0.date < $1.date }
        Page {
            let missing = file.sessions.filter { file.needsReviewNote($0, at: .now) }.count
            let unlinked = file.units.isEmpty ? 0 : file.sessions.filter { file.needsUnits($0, at: .now) }.count
            HStack(alignment: .bottom) {
                PageHeader(title: "회차", subtitle: file.sessions.isEmpty ? "회차가 아직 없습니다"
                           : (["회차 \(file.sessions.count)개"] + (missing > 0 ? ["복습 노트 없음 \(missing)"] : [])
                              + (unlinked > 0 ? ["단원 없음 \(unlinked)"] : [])).joined(separator: " · "))
                Spacer()
                Button("회차 추가") { adding = true }.buttonStyle(.pointing(.borderedProminent))
                    .help("리시테이션, 보강, 실험처럼 시간표에 없는 수업")
            }
            if file.course.schedule.isEmpty { schedule(file) }
            if !untouched.isEmpty { untouchedCard }
            // shortcut: worked out when the page redraws, not on a timer, so a class ending while the page sits open
            // keeps its suggestion until the next change; a TimelineView left an empty gap whenever nothing was suggested.
            if let item = workspace.suggestedSession(for: course, now: .now) {
                Block("다음 강의", note: "시간표로 제안한 회차") { SuggestedSessionRow(item: item, openNote: openNote) { editingTimes = true } }
            }
            if !weeks.isEmpty {
                // One timeline down the page instead of a card per week: a row gets the full width for its title. The rail
                // is the course color as far as the term has come and gray beyond, so where now is reads at a glance.
                let items = timeline(weeks: weeks, exams: exams)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        let above: Bool? = i == 0 ? nil : item.held
                        let below: Bool? = i == items.count - 1 ? nil : items[i + 1].held
                        switch item {
                        case .week(let sessions, let month):
                            let thisWeek = workspace.calendar.startOfWeek(containing: sessions[0].date) == workspace.calendar.startOfWeek(containing: .now)
                            // Quieter than a session's title: it only divides; the dates are in the gutter.
                            TimelineLine(above: above, below: below, month: month) {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Text("\(sessions[0].week)주차").font(Theme.Typeface.caption.weight(.semibold))
                                        .foregroundStyle(thisWeek ? accent.ink : Theme.Palette.textTertiary)
                                    if thisWeek { Chip("이번 주", tone: .accent) }
                                }
                                .padding(.top, i == 0 ? Theme.Space.s : Theme.Space.l)
                                .padding(.bottom, Theme.Space.xs)
                                .padding(.leading, SessionRow.rowPadding)
                            }
                        case .month(let date):
                            TimelineLine(above: above, below: below, month: date) { Color.clear.frame(height: 18) }
                        case .exam(let exam, let date):
                            TimelineLine(above: above, below: below, marker: true) {
                                Text((exam.title.isEmpty ? exam.kind.label : exam.title) + " · " + date.formatted(.dateTime.month().day().weekday()))
                                    .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.danger)
                                    .padding(.vertical, Theme.Space.m).padding(.leading, SessionRow.rowPadding)
                            }
                        case .session(let session):
                            let end = session.end(schedule: file.course.schedule, calendar: workspace.calendar)
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                SessionRow(course: course, session: session, now: context.date, end: end, openNote: openNote, above: above, below: below)
                            }
                            .fileDrop { workspace.importFiles($0, into: CourseFolder.lectures.rawValue, week: session.week, session: session.id, course: course.id) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $editingTimes) { ClassTimesSheet(course: course) }
        .sheet(isPresented: $adding) { AddSessionSheet(course: course) }
        // Reads the course's notes from disk, so not on every redraw.
        .task(id: file.sessions) { untouched = workspace.untouchedFutureSessions(course, now: .now) }
    }

    /// Weeks, their sessions and the midterm and final where they fall, flattened so each line knows its neighbors.
    func timeline(weeks: [[Session]], exams: [(exam: Exam, date: Date)]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var after = Date.distantPast
        let cal = workspace.calendar
        var month: Int?
        // The gutter shows only the day, so the month is marked where it changes: on the week's line, or on a line of
        // its own when it turns partway through a week.
        func opens(_ date: Date) -> Bool {
            let m = cal.component(.year, from: date) * 12 + cal.component(.month, from: date)
            defer { month = m }
            return m != month
        }
        for sessions in weeks {
            items += exams.filter { $0.date > after && $0.date <= sessions[0].date }.map { .exam($0.exam, $0.date) }
            items.append(.week(sessions, month: opens(sessions[0].date) ? sessions[0].date : nil))
            for (i, s) in sessions.enumerated() {
                if i > 0 && opens(s.date) { items.append(.month(s.date)) }
                items.append(.session(s))
            }
            after = sessions.last!.date
        }
        return items + exams.filter { $0.date > after }.map { .exam($0.exam, $0.date) }
    }

    /// The weekly times are a course property, edited with the rest of the course; here they only suggest sessions.
    func schedule(_ file: CourseFile) -> some View {
        let slots = file.course.schedule
        let summary = slots.map { "\(ClassTime.weekdayNames[$0.weekday - 1]) \(TimeMenu.range($0.startMinute, $0.endMinute))" + ($0.room.isEmpty ? "" : " \($0.room)") }
        return Card {
            CardRow(last: true) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("수업 시간")
                    Text(slots.isEmpty ? "수업 시간을 넣으면 다음 강의를 회차로 제안합니다" : summary.joined(separator: " · "))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer(minLength: Theme.Space.m)
                Button(slots.isEmpty ? "수업 시간 넣기" : "바꾸기") { editingTimes = true }.buttonStyle(.ghost)
            }
            .contentShape(.rect)
            .contextMenu { Button(slots.isEmpty ? "수업 시간 넣기…" : "수업 시간 바꾸기…") { editingTimes = true } }
        }
    }

    /// Left over from when whole terms were made ahead; deleted only once the user agrees.
    var untouchedCard: some View {
        let shown = untouched.prefix(4)
        return NoticeCard(title: "미리 만든 빈 회차 \(untouched.count)개",
                          detail: "노트, 녹음, 출석, 자료, 단원이 하나도 연결되지 않은 앞으로의 회차입니다. 지우면 수업 때마다 제안되는 회차로 만들면 됩니다.",
                          systemImage: "calendar.badge.minus") {
            Button("지우기…") { confirmingDelete = true }.buttonStyle(.pointing(.bordered))
        } rows: {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && untouched.count <= shown.count) {
                    Text(s.date.formatted(.dateTime.month().day().weekday().hour().minute())).monospacedDigit()
                    Spacer()
                    Text(course.file.name(of: s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if untouched.count > shown.count {
                CardRow(last: true) { EmptyLine("외 \(untouched.count - shown.count)개") }
            }
        }
        .confirmationDialog("빈 회차 \(untouched.count)개를 지울까요?", isPresented: $confirmingDelete) {
            Button("지우기", role: .destructive) {
                let ids = Set(untouched.map(\.id))
                workspace.run(SessionRemove(course: course.id, sessions: Array(ids)))
            }
        } message: {
            Text("연결된 것이 없는 회차만 지웁니다.")
        }
    }
}

/// The lecture the schedule says is under way or next, not made yet: a dashed row. Starting its rough note or a
/// recording makes the session first; 휴강 saves it cancelled, so the suggestion moves to the next lecture.
struct SuggestedSessionRow: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    /// On Today: the time and the course, as in 오늘 수업.
    var showsCourse = false
    let openNote: (UUID) -> Void
    /// On the sessions page, where a wrong suggestion is the cue that the class times changed.
    var editTimes: (() -> Void)?

    var body: some View {
        let date = item.suggestion.date
        let today = workspace.isStudyToday(date)
        HStack(spacing: Theme.Space.m) {
            if showsCourse {
                Text(date.formatted(date: .omitted, time: .shortened)).timeColumn().font(Theme.Typeface.caption).monospacedDigit().fixedSize()
                CourseDot(color: workspace.accent(item.courseId).color)
                Text("\(workspace.course(item.courseId)?.title ?? "") · \(item.name)").lineLimit(1)
                    .help("시간표로 제안한 회차")
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                    Text(date.formatted(.dateTime.weekday()) + " " + TimeMenu.label(workspace.calendar.component(.hour, from: date) * 60 + workspace.calendar.component(.minute, from: date))).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
                .frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("강의").font(Theme.Typeface.bodyStrong)
                    Text(item.name + (item.suggestion.room.isEmpty ? "" : " · \(item.suggestion.room)"))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: Theme.Space.m)
            SuggestedSessionActions(item: item, compact: showsCourse, openNote: openNote, editTimes: editTimes).fixedSize()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .opacity(today ? 1 : 0.85)
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
    }
}

struct SuggestedSessionActions: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    /// In Today's narrow column the note button is an icon.
    var compact = false
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let today = workspace.isStudyToday(item.suggestion.date)
        HStack(spacing: Theme.Space.s) {
            if today {
                Button { SuggestedSessionItems.roughNote(item, workspace, openNote) } label: {
                    if compact { Image(systemName: "square.and.pencil").accessibilityLabel("러프 노트") } else { Text("러프 노트") }
                }
                .buttonStyle(.pointing(.borderedProminent))
                .help("회차를 만들고 러프 노트를 엽니다")
            } else {
                Button("만들기") { SuggestedSessionItems.make(item, workspace) }.buttonStyle(.pointing(.bordered))
            }
            Menu { SuggestedSessionItems(item: item, primary: false, openNote: openNote, editTimes: editTimes) } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help("녹음, 결석, 휴강")
        }
    }
}

/// The suggestion's ⋯ menu items; with `primary`, led by the row's own button, for the row's context menu.
struct SuggestedSessionItems: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    let primary: Bool
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let today = workspace.isStudyToday(item.suggestion.date)
        if primary {
            if today { Button("러프 노트 열기") { Self.roughNote(item, workspace, openNote) } } else { Button("회차 만들기") { Self.make(item, workspace) } }
        }
        if today { Button("회차만 만들기") { Self.make(item, workspace) } }
        Button("녹음 시작 (한국어)") { record(Locale(identifier: "ko-KR")) }.disabled(workspace.recorder.isActive)
        Button("녹음 시작 (영어)") { record(Locale(identifier: "en-US")) }.disabled(workspace.recorder.isActive)
        Divider()
        // An absence known ahead makes the session, like 휴강 does, so it has something to hang on.
        Button("결석으로 표시") { mark(.absent) }
        Button("공결로 표시") { mark(.excused) }
        Divider()
        Button("휴강") { Self.make(item, workspace, cancelled: true) }
        if let editTimes {
            Divider()
            Button("수업 시간 바꾸기…", action: editTimes)
        }
    }

    func mark(_ state: AttendanceState) {
        if let s = Self.make(item, workspace) { workspace.run(AttendanceSet(course: item.courseId, session: s.id, state: state)) }
    }

    @discardableResult
    static func make(_ item: Workspace.SuggestedSession, _ workspace: Workspace, cancelled: Bool = false) -> Session? {
        workspace.createSession(at: item.suggestion.date, cancelled: cancelled, in: item.courseId)
    }

    static func roughNote(_ item: Workspace.SuggestedSession, _ workspace: Workspace, _ openNote: (UUID) -> Void) {
        if let s = make(item, workspace), let id = workspace.note(.rough, of: s.id, in: item.courseId) { openNote(id) }
    }

    func record(_ locale: Locale) {
        if let s = Self.make(item, workspace) { workspace.record(s.id, in: item.courseId, locale: locale) }
    }
}

/// A session off the weekly schedule: a recitation, a makeup, or a 휴강 the suggestion never offered.
struct AddSessionSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State private var date: Date
    @State private var cancelled = false

    init(course: LoadedCourse) {
        self.course = course
        let today = Calendar.current.startOfDay(for: .now)
        _date = State(initialValue: Calendar.current.date(byAdding: .hour, value: 18, to: today) ?? today)
    }

    var body: some View {
        SheetForm(title: "회차 추가", confirm: "추가") {
            FormRow(label: "날짜") { DateChip(date: $date) }
            FormRow(label: "휴강", last: true) { Switch(isOn: $cancelled) }
        } onConfirm: {
            workspace.createSession(at: date, cancelled: cancelled, in: course.id)
            dismiss()
        }
    }
}

/// The units a session covers, linked or unlinked in place. A held class with none is flagged, since its review
/// never reaches the unit queue (docs/SPEC.md "복습 스케줄러").
struct SessionUnitsPicker: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let session: Session
    /// The icon alone, when the row's title already names the units.
    var compact = false

    var body: some View {
        let file = course.file
        let linked = file.units(of: session)
        let shown = UnitTree.deepest(linked, in: file.units)
        let missing = file.needsUnits(session, at: .now)
        if !file.units.isEmpty && (!linked.isEmpty || !session.skipsReview) {
            SearchPicker(options: UnitTree.outline(file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) },
                         isSelected: { id in linked.contains { $0.id == id } },
                         pick: { id in workspace.run(UnitLink(course: course.id, unit: id, sessions: [session.id], linked: !session.unitIds.contains(id))) },
                         multiple: true, prompt: "단원 검색", flexible: true) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: missing ? "exclamationmark.triangle.fill" : linked.isEmpty ? "plus" : "link")
                    if !compact {
                        Text(shown.isEmpty ? (missing ? "단원 연결 필요" : "단원 연결") : shown.map(\.title).joined(separator: " · "))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(Theme.Typeface.caption.weight(missing ? .semibold : .regular))
                .foregroundStyle(missing ? Theme.Palette.warning : linked.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                .contentShape(.rect)
            }
            // The label truncates on a narrow row, so the tooltip carries every title.
            .help(missing ? "연결된 단원이 없어 이 수업은 단원 복습에 잡히지 않습니다" : shown.isEmpty ? "이 회차가 다룬 단원" : shown.map(\.title).joined(separator: "\n"))
        }
    }
}

enum TimelineItem: Identifiable {
    /// With the month when the week opens one.
    case week([Session], month: Date?)
    /// A month that begins partway through a week.
    case month(Date)
    case exam(Exam, Date)
    case session(Session)

    var id: String {
        switch self {
        case .week(let s, _): "week-\(s[0].week)"
        case .month(let d): "month-\(d.timeIntervalSinceReferenceDate)"
        case .exam(let e, _): "exam-\(e.id)"
        case .session(let s): s.id.uuidString
        }
    }

    /// Already reached, judged at draw time; the rail is colored up to here.
    var held: Bool {
        switch self {
        case .week(let s, _): s[0].date <= .now
        case .month(let d): d <= .now
        case .exam(_, let d): d <= .now
        case .session(let s): s.date <= .now
        }
    }
}

/// A line of the timeline that isn't a session: the gutter blank or naming a new month, the rail running through.
struct TimelineLine<Content: View>: View {
    @Environment(\.accent) private var accent
    let above: Bool?
    let below: Bool?
    var month: Date?
    var marker = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Level with the line's text, which sits at the bottom of its padding.
            Text(month?.formatted(.dateTime.month()) ?? "").font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize().frame(width: SessionRow.gutter).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, Theme.Space.xs)
            Rail(above: above, below: below) {
                // A midterm or final: a diamond on the rail.
                if marker { Rectangle().fill(Theme.Palette.danger).frame(width: 8, height: 8).rotationEffect(.degrees(45)) }
            }
            .frame(maxHeight: .infinity)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The rail through one line: the half above and below the dot, each in the course color once held and gray ahead.
/// `dotY` puts the dot level with the row's title; nil centers it.
struct Rail<Dot: View>: View {
    @Environment(\.accent) private var accent
    let above: Bool?
    let below: Bool?
    var dotY: CGFloat?
    @ViewBuilder var dot: Dot

    var body: some View {
        GeometryReader { proxy in
            let y = dotY ?? proxy.size.height / 2
            VStack(spacing: 0) {
                Rectangle().fill(style(above, else: below, fadingUp: true)).frame(width: 2, height: y)
                Rectangle().fill(style(below, else: above, fadingUp: false)).frame(width: 2)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { dot.frame(height: y * 2) }
        }
        .frame(width: SessionRow.railWidth)
    }

    /// At either end the rail fades out from its neighbor's color instead of stopping square.
    func style(_ held: Bool?, else neighbor: Bool?, fadingUp: Bool) -> AnyShapeStyle {
        if let held { return AnyShapeStyle(color(held)) }
        guard let neighbor else { return AnyShapeStyle(Color.clear) }
        let c = color(neighbor)
        return AnyShapeStyle(LinearGradient(colors: [c, c.opacity(0)], startPoint: fadingUp ? .bottom : .top, endPoint: fadingUp ? .top : .bottom))
    }

    func color(_ held: Bool) -> Color { held ? accent.color.opacity(0.5) : Theme.Palette.line }
}

/// Date, what the class covered, then only the notes that exist. Creating notes, attendance and cancelling live in one menu,
/// except today's rough note, which is a single click away (docs/SPEC.md "강의 회차").
struct SessionRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let session: Session
    var now = Date.now
    /// From the class times; nil for a class off the schedule, which then never shows as under way.
    var end: Date?
    let openNote: (UUID) -> Void
    @State private var playing: Recording?
    @State private var confirmingDelete = false
    @State private var deleteRefusal: String?
    /// The rail above and below this row's dot: nil at the ends, true once held.
    var above: Bool?
    var below: Bool?
    @State private var hovering = false
    static let rowPadding: CGFloat = 8
    static let gutter: CGFloat = 26
    static let railWidth: CGFloat = 22
    /// Level with the title line's middle.
    static let dotY: CGFloat = rowPadding + 10

    var body: some View {
        let cancelled = session.isCancelled
        let ongoing = !cancelled && end.map { now >= session.date && now < $0 } ?? false
        let ahead = session.date > now
        HStack(alignment: .top, spacing: 0) {
            // The day large, the weekday under it; the month is marked on the timeline where it changes.
            VStack(spacing: 0) {
                // The bare number: Korean's day format adds 일.
                Text("\(workspace.calendar.component(.day, from: session.date))").font(Theme.Typeface.figureMedium.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(ongoing ? accent.ink : Theme.Palette.text)
                Text(session.date.formatted(.dateTime.weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(width: Self.gutter)
            .padding(.top, Self.rowPadding - 2)
            .opacity(ahead ? 0.55 : 1)
            Rail(above: above, below: below, dotY: Self.dotY) {
                dot(progress: ongoing ? end.map { now.timeIntervalSince(session.date) / $0.timeIntervalSince(session.date) } : nil, ahead: ahead, cancelled: cancelled)
            }
            // One stack, so a right click anywhere on the row opens the ⋯ menu's items.
            HStack(alignment: .top, spacing: Theme.Space.m) { row }
                .padding(Self.rowPadding)
                .background(hovering ? Theme.Palette.text.opacity(0.04) : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(.rect)
                .onHover { hovering = $0 }
                .contextMenu { menuItems }
        }
    }

    @ViewBuilder var row: some View {
        let recordings = course.file.recordings.filter { $0.sessionId == session.id }
        let recorder = workspace.recorder
        let recordingThis = recorder.isActive && recordings.contains { $0.id == recorder.recording?.id }
        let attendance = course.file.attendance.first { $0.sessionId == session.id }?.state ?? .present
        let calendar = workspace.calendar
        let cancelled = session.isCancelled
        // Sessions imported from Notion carry a date only, stored at midnight.
        let timeKnown = calendar.dateComponents([.hour, .minute], from: session.date) != DateComponents(hour: 0, minute: 0)
        let today = workspace.isStudyToday(session.date)
        let late = cancelled ? nil : AttendanceState.steps.first { $0.value == attendance && attendance != .present }
        let ongoing = !cancelled && end.map { now >= session.date && now < $0 } ?? false
        // Classes still ahead are drawn faint, like the suggested one, so the held ones read as the record.
        let ahead = session.date > now
        let time = calendar.dateComponents([.hour, .minute], from: session.date)
        let clock = timeKnown ? TimeMenu.label((time.hour ?? 0) * 60 + (time.minute ?? 0)) : ""
        // The date and weekday are in the gutter, so the line under the title carries only the time and how far off.
        let when: String? = ahead ? Self.ahead(session.date, clock: clock, now: now, calendar: calendar) : clock.isEmpty ? nil : clock
        // The title says what the class covered: its topic, else its units, else its name (9주차-1), which only repeats
        // the week line and otherwise lives in the tooltip. The kind (실험) is left out: a lab is a class like any other.
        let name = course.file.name(of: session)
        let units = UnitTree.deepest(course.file.units(of: session), in: course.file.units)
        let title = !session.topic.isEmpty ? session.topic : !units.isEmpty ? units.map(\.title).joined(separator: " · ") : name
        // Units that only restate the title (Lab04 Thin-layer chromatography under Thin-layer chromatography) shrink to their icon.
        let unitsInTitle = !units.isEmpty && units.allSatisfy { session.topic.isEmpty || $0.title.localizedCaseInsensitiveContains(session.topic) || session.topic.localizedCaseInsensitiveContains($0.title) }
        let left = ongoing ? end.map { Text("\(Int($0.timeIntervalSince(now) / 60) + 1)분 남음").fontWeight(.semibold).foregroundStyle(accent.ink) } : nil
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1).help(name)
                    .strikethrough(cancelled).foregroundStyle(cancelled ? Theme.Palette.textTertiary : Theme.Palette.text)
                // Only a class missed or late: present is the rule and says nothing.
                if let late { Text(late.label).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(late.tint).fixedSize() }
            }
            HStack(spacing: Theme.Space.s) {
                if let line = left ?? when.map({ Text($0) }) {
                    line.font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit().lineLimit(1).fixedSize()
                }
                if !cancelled { SessionUnitsPicker(course: course, session: session, compact: unitsInTitle) }
            }
        }
        // Takes the room the fixed slots leave, so the topic and units truncate before anything else moves.
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(ahead ? 0.55 : 1)
        if !cancelled {
            HStack(spacing: Theme.Space.s) {
                if recordingThis {
                    Label("녹음 중", systemImage: "waveform").foregroundStyle(Theme.Palette.danger)
                        .symbolEffect(.variableColor.iterative, isActive: recorder.state == .recording)
                } else if let last = recordings.last {
                    SessionSlot(recordings.count > 1 ? "녹음 \(recordings.count)" : "녹음", symbol: "waveform", help: "녹음 듣기와 받아쓰기", fixed: false) { playing = last }
                } else if today && !recorder.isActive {
                    SessionSlot("녹음", symbol: "record.circle", help: "이 수업을 녹음하고 받아씁니다", fixed: false) { record(Locale(identifier: "ko-KR")) }
                }
                // No empty recording slot: it sits leftmost, so the note slots line up without it and the topic keeps the room.
                SessionNoteSlots(file: course.file, session: session, offersRough: today, openNote: openNote, create: open)
            }
        }
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless).pointingHand()
        .fixedSize()
        .help("노트, 출석, 녹음, 종류, 삭제")
        .confirmationDialog("\(course.file.name(of: session)) 회차를 지울까요?", isPresented: $confirmingDelete) {
            Button("지우기", role: .destructive) {
                workspace.run(SessionRemove(course: course.id, sessions: [session.id]))
            }
        } message: {
            Text("같은 주의 다른 회차 번호는 그대로입니다.")
        }
        .alert("이 회차는 지울 수 없습니다", isPresented: Binding(get: { deleteRefusal != nil }, set: { if !$0 { deleteRefusal = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(deleteRefusal ?? "")
        }
        .sheet(item: $playing) { RecordingPlayer(courseId: course.id, store: course.store, recording: $0, title: "\(course.file.course.title) · \(course.file.name(of: session))") }
    }

    /// The ⋯ menu's items, also the row's context menu.
    @ViewBuilder var menuItems: some View {
        let recordings = course.file.recordings.filter { $0.sessionId == session.id }
        let recorder = workspace.recorder
        let attendance = course.file.attendance.first { $0.sessionId == session.id }?.state ?? .present
        let cancelled = session.isCancelled
        let takesAttendance = workspace.can(AttendanceSet(course: course.id, session: session.id, state: .absent))
        Button(session.roughNoteId == nil ? "러프 노트 만들기" : "러프 노트 열기") { open(.rough) }
        Button(session.reviewNoteId == nil ? "복습 노트 만들기" : "복습 노트 열기") { open(.review) }
        Toggle("복습 필요 없음", isOn: Binding(get: { session.skipsReview }, set: { workspace.setSkipsReview($0, of: session.id, in: course.id) }))
        // Also ahead of the class, for an absence known in advance; it counts toward the caps once the class starts.
        if takesAttendance {
            Picker("출석", selection: Binding(get: { attendance }, set: setAttendance)) {
                ForEach(AttendanceState.steps, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
        Divider()
        Button("녹음 시작 (한국어)") { record(Locale(identifier: "ko-KR")) }.disabled(recorder.isActive)
        Button("녹음 시작 (영어)") { record(Locale(identifier: "en-US")) }.disabled(recorder.isActive)
        ForEach(Array(recordings.enumerated()), id: \.element.id) { i, r in
            Button("녹음 \(i + 1) 듣기 (\(RecordingTime.label(r.duration)))") { playing = r }
        }
        Divider()
        Toggle("휴강", isOn: Binding(get: { cancelled }, set: { workspace.run(SessionSet(course: course.id, session: session.id, cancelled: .set($0))) }))
        Divider()
        Button("회차 삭제…", role: .destructive) {
            deleteRefusal = workspace.refusal(SessionRemove(course: course.id, sessions: [session.id]))
            if deleteRefusal == nil { confirmingDelete = true }
        }
    }

    func record(_ locale: Locale) {
        workspace.record(session.id, in: course.id, locale: locale)
    }

    /// Filled in the course color once held, hollow while ahead or cancelled, and while under way a ring filling round as
    /// the class goes. The page-colored fill keeps the rail from showing through.
    @ViewBuilder func dot(progress: Double?, ahead: Bool, cancelled: Bool) -> some View {
        if let progress {
            ZStack {
                Circle().stroke(accent.color.opacity(0.22), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress).stroke(accent.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(accent.color).frame(width: 6, height: 6)
            }
            .frame(width: 16, height: 16)
            .background(Theme.Palette.page, in: .circle)
        } else if ahead || cancelled {
            Circle().strokeBorder(Theme.Palette.lineStrong, lineWidth: 1.5)
                .background(Theme.Palette.page, in: .circle).frame(width: 10, height: 10)
        } else {
            Circle().fill(accent.color).frame(width: 8, height: 8)
                .padding(Theme.Space.xxs).background(Theme.Palette.page, in: .circle)
        }
    }

    /// `오늘 오후 1:00`, `내일 오후 1:00`, then `3일 후`.
    static func ahead(_ date: Date, clock: String, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "오늘 \(clock)"
        case 1: return "내일 \(clock)"
        default: return "\(days)일 후"
        }
    }

    func open(_ kind: NoteKind) {
        if let id = workspace.note(kind, of: session.id, in: course.id) { openNote(id) }
    }

    func setAttendance(_ state: AttendanceState) {
        workspace.run(AttendanceSet(course: course.id, session: session.id, state: state))
    }
}

/// One action of a session row: an icon and a short word, all in one plain style. Whether it exists, is offered or is
/// missing shows only in the icon and color, and the fixed width keeps each kind in one column down the page.
struct SessionSlot: View {
    // Fits an icon and two letters (and caption-sized 복습 없음) with little to spare, so neighbors sit close.
    static let width: CGFloat = 56
    static var empty: some View { Color.clear.frame(width: width, height: 1) }

    let title: String
    let symbol: String
    var tint: Color = Theme.Palette.textSecondary
    let help: String
    /// Off for the recording, which sits leftmost and lines up with nothing.
    var fixed = true
    let action: () -> Void

    init(_ title: String, symbol: String, tint: Color = Theme.Palette.textSecondary, help: String, fixed: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.help = help
        self.fixed = fixed
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .buttonStyle(.ghost)
            .tint(tint)
            .help(help)
            // Trailing, so the spare room falls between slots and every gap reads the same.
            .frame(width: fixed ? Self.width : nil, alignment: .trailing)
    }
}

/// The rough and review note slots, shared by the sessions page and a unit's classes so both read alike.
struct SessionNoteSlots: View {
    @Environment(\.accent) private var accent
    let file: CourseFile
    let session: Session
    /// Today's class offers its rough note before it exists.
    var offersRough = false
    let openNote: (UUID) -> Void
    let create: (NoteKind) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let id = session.roughNoteId {
                SessionSlot("러프", symbol: "doc.text", help: "러프 노트 열기") { openNote(id) }
            } else if offersRough {
                SessionSlot("러프", symbol: "plus", tint: accent.ink, help: "러프 노트를 만듭니다") { create(.rough) }
            } else {
                SessionSlot.empty
            }
            if let id = session.reviewNoteId {
                // Made but not written yet: still in the missing note's warning color.
                if session.reviewNoteUnfinished {
                    SessionSlot("복습", symbol: "square.and.pencil", tint: Theme.Palette.warning, help: "복습 노트 열기 · 작성 중") { openNote(id) }
                } else {
                    SessionSlot("복습", symbol: "doc.text", help: "복습 노트 열기") { openNote(id) }
                }
            } else if file.needsReviewNote(session, at: .now) {
                SessionSlot("복습", symbol: "plus", tint: Theme.Palette.warning, help: "복습 노트를 만듭니다") { create(.review) }
            } else if session.skipsReview {
                Text("복습 없음").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: SessionSlot.width, alignment: .trailing)
            } else {
                SessionSlot.empty
            }
        }
    }
}

extension AttendanceState {
    @MainActor static let steps: [StepToggle<AttendanceState>.Option] = [
        .init(value: .present, label: "출석", tint: Theme.Palette.success),
        .init(value: .late, label: "지각", tint: Theme.Palette.warning),
        .init(value: .absent, label: "결석", tint: Theme.Palette.danger),
        .init(value: .excused, label: "공결", tint: Theme.Palette.textSecondary),
    ]

    var label: String {
        switch self {
        case .present: "출석"
        case .late: "지각"
        case .absent: "결석"
        case .excused: "공결"
        }
    }
}

