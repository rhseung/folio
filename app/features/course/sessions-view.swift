import FolioActions
import FolioDomain
import SwiftUI

/// Sessions are made as classes happen: the weekly schedule only suggests the next lecture, and the rest are added by hand (docs/SPEC.md "강의 회차").
struct SessionsView: View {
    @Environment(\.accent) private var accent
    @State private var model: SessionsModel
    let course: LoadedCourse
    let openNote: (UUID) -> Void
    @State private var editingTimes = false
    @State private var adding = false
    @State private var confirmingDelete = false

    init(workspace: Workspace, course: LoadedCourse, openNote: @escaping (UUID) -> Void) {
        _model = State(initialValue: SessionsModel(workspace: workspace, courseId: course.id))
        self.course = course
        self.openNote = openNote
    }

    var body: some View {
        let file = course.file
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .sessionsTitle), subtitle: model.subtitle(file))
                Spacer()
                Button(.sessionsAdd) { adding = true }.buttonStyle(.pointing(.borderedProminent))
                    .help(Text(.sessionsAddHelp))
            }
            if file.course.schedule.isEmpty { schedule }
            if !model.untouched.isEmpty { untouchedCard }
            // shortcut: worked out when the page redraws, not on a timer, so a class ending while the page sits open
            // keeps its suggestion until the next change; a TimelineView left an empty gap whenever nothing was suggested.
            if let item = model.suggested(course) {
                Block(String(localized: .sessionsNext), note: String(localized: .sessionsSuggested)) {
                    SuggestedSessionRow(item: item, openNote: openNote) { editingTimes = true }
                }
            }
            let rows = model.timeline(file)
            if !rows.isEmpty {
                // One timeline down the page instead of a card per week: a row gets the full width for its title. The rail
                // is the course color as far as the term has come and gray beyond, so where now is reads at a glance.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in line(row, file: file) }
                }
            }
        }
        .sheet(isPresented: $editingTimes) { ClassTimesSheet(workspace: model.workspace, course: course) }
        .sheet(isPresented: $adding) { AddSessionSheet(course: course) }
        .task(id: file.sessions) { model.loadUntouched(course) }
    }

    @ViewBuilder func line(_ row: SessionsModel.TimelineRow, file: CourseFile) -> some View {
        let (above, below) = (row.above, row.below)
        switch row.item {
        case .week(let sessions, let month):
            let thisWeek = model.isThisWeek(sessions[0].date)
            // Quieter than a session's title: it only divides; the dates are in the gutter.
            TimelineLine(above: above, below: below, month: month) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(.sessionsWeek(sessions[0].week)).font(Theme.Typeface.caption.weight(.semibold))
                        .foregroundStyle(thisWeek ? accent.ink : Theme.Palette.textTertiary)
                    if thisWeek { Chip(String(localized: .sessionsThisWeek), tone: .accent) }
                }
                .padding(.top, row.first ? Theme.Space.s : Theme.Space.l)
                .padding(.bottom, Theme.Space.xs)
                .padding(.leading, SessionRow.rowPadding)
            }
        case .month(let date):
            TimelineLine(above: above, below: below, month: date) { Color.clear.frame(height: 18) }
        case .exam(let exam, let date):
            TimelineLine(above: above, below: below, marker: true) {
                Text(model.examLine(exam, date))
                    .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.danger)
                    .padding(.vertical, Theme.Space.m).padding(.leading, SessionRow.rowPadding)
            }
        case .session(let session):
            let end = model.end(of: session, in: file)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                SessionRow(model: model, course: course, session: session, now: context.date, end: end, openNote: openNote, above: above, below: below)
            }
            .fileDrop { model.importFiles($0, into: session) }
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

    /// Left over from when whole terms were made ahead; deleted only once the user agrees.
    var untouchedCard: some View {
        let shown = model.untouchedShown
        return NoticeCard(title: String(localized: .sessionsUntouchedTitle(model.untouched.count)),
                          detail: String(localized: .sessionsUntouchedDetail),
                          systemImage: "calendar.badge.minus") {
            Button(.sessionsRemoveEllipsis) { confirmingDelete = true }.buttonStyle(.pointing(.bordered))
        } rows: {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && model.untouchedMore == 0) {
                    Text(s.date.formatted(.dateTime.month().day().weekday().hour().minute())).monospacedDigit()
                    Spacer()
                    Text(course.file.name(of: s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if model.untouchedMore > 0 {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(model.untouchedMore))) }
            }
        }
        .confirmationDialog(String(localized: .sessionsUntouchedConfirm(model.untouched.count)), isPresented: $confirmingDelete) {
            Button(.sessionsRemove, role: .destructive) { model.removeUntouched() }
        } message: {
            Text(.sessionsUntouchedConfirmMessage)
        }
    }
}

/// The lecture the schedule says is under way or next, not made yet: a dashed row. Starting its rough note or a
/// recording makes the session first; 휴강 saves it cancelled, so the suggestion moves to the next lecture.
struct SuggestedSessionRow: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
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
                    .help(Text(.sessionsSuggested))
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                    Text(date.formatted(.dateTime.weekday()) + " " + TimeMenu.label(workspace.calendar.component(.hour, from: date) * 60 + workspace.calendar.component(.minute, from: date))).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
                .frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(.sessionsLecture).font(Theme.Typeface.bodyStrong)
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
                    if compact { Image(systemName: "square.and.pencil").accessibilityLabel(Text(.sessionsRoughNote)) } else { Text(.sessionsRoughNote) }
                }
                .buttonStyle(.pointing(.borderedProminent))
                .help(Text(.sessionsRoughNoteHelp))
            } else {
                Button(.sessionsMake) { SuggestedSessionItems.make(item, workspace) }.buttonStyle(.pointing(.bordered))
            }
            Menu { SuggestedSessionItems(item: item, primary: false, openNote: openNote, editTimes: editTimes) } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(.sessionsSuggestionMenuHelp))
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
            if today { Button(.sessionsOpenRoughNote) { Self.roughNote(item, workspace, openNote) } } else { Button(.sessionsMakeSession) { Self.make(item, workspace) } }
        }
        if today { Button(.sessionsMakeSessionOnly) { Self.make(item, workspace) } }
        Button(.sessionsRecordKorean) { record(Locale(identifier: "ko-KR")) }.disabled(workspace.recorder.isActive)
        Button(.sessionsRecordEnglish) { record(Locale(identifier: "en-US")) }.disabled(workspace.recorder.isActive)
        Divider()
        // An absence known ahead makes the session, like 휴강 does, so it has something to hang on.
        Button(.sessionsMarkAbsent) { mark(.absent) }
        Button(.sessionsMarkExcused) { mark(.excused) }
        Divider()
        Button(.sessionsCancelled) { Self.make(item, workspace, cancelled: true) }
        if let editTimes {
            Divider()
            Button(.sessionsClassTimesChangeEllipsis, action: editTimes)
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
        SheetForm(title: String(localized: .sessionsAdd), confirm: String(localized: .commonAdd)) {
            FormRow(label: String(localized: .sessionsDate)) { DateChip(date: $date) }
            FormRow(label: String(localized: .sessionsCancelled), last: true) { Switch(isOn: $cancelled) }
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
                         multiple: true, prompt: String(localized: .sessionsUnitsSearch), flexible: true) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: missing ? "exclamationmark.triangle.fill" : linked.isEmpty ? "plus" : "link")
                    if !compact {
                        Text(shown.isEmpty ? String(localized: missing ? .sessionsUnitsNeeded : .sessionsUnitsLink) : shown.map(\.title).joined(separator: " · "))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(Theme.Typeface.caption.weight(missing ? .semibold : .regular))
                .foregroundStyle(missing ? Theme.Palette.warning : linked.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                .contentShape(.rect)
            }
            // The label truncates on a narrow row, so the tooltip carries every title.
            .help(missing ? String(localized: .sessionsUnitsMissingHelp) : shown.isEmpty ? String(localized: .sessionsUnitsHelp) : shown.map(\.title).joined(separator: "\n"))
        }
    }
}

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
                if marker { Rectangle().fill(Theme.Palette.danger).frame(width: 8, height: 8).rotationEffect(.degrees(45)) }
            }
            .frame(maxHeight: .infinity)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

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
    @Environment(\.accent) private var accent
    let model: SessionsModel
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
        let ongoing = model.isOngoing(session, end: end, now: now)
        let ahead = session.date > now
        HStack(alignment: .top, spacing: 0) {
            // The day large, the weekday under it; the month is marked on the timeline where it changes.
            VStack(spacing: 0) {
                // The bare number: Korean's day format adds 일.
                Text("\(model.calendar.component(.day, from: session.date))").font(Theme.Typeface.figureMedium.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(ongoing ? accent.ink : Theme.Palette.text)
                Text(session.date.formatted(.dateTime.weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(width: Self.gutter)
            .padding(.top, Self.rowPadding - 2)
            .opacity(ahead ? 0.55 : 1)
            Rail(above: above, below: below, dotY: Self.dotY) {
                dot(progress: model.progress(session, end: end, now: now), ahead: ahead, cancelled: session.isCancelled)
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
        let file = course.file
        let recordings = model.recordings(of: session, in: file)
        let recorder = model.workspace.recorder
        let recordingThis = recorder.isActive && recordings.contains { $0.id == recorder.recording?.id }
        let cancelled = session.isCancelled
        let today = model.isToday(session.date)
        let late = model.lateMark(session, in: file)
        // Classes still ahead are drawn faint, like the suggested one, so the held ones read as the record.
        let ahead = session.date > now
        let left = model.isOngoing(session, end: end, now: now)
            ? end.map { Text(model.minutesLeft(until: $0, now: now)).fontWeight(.semibold).foregroundStyle(accent.ink) } : nil
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                Text(model.title(of: session, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1).help(file.name(of: session))
                    .strikethrough(cancelled).foregroundStyle(cancelled ? Theme.Palette.textTertiary : Theme.Palette.text)
                if let late { Text(late.label).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(late.tint).fixedSize() }
            }
            HStack(spacing: Theme.Space.s) {
                if let line = left ?? model.when(session, now: now).map({ Text($0) }) {
                    line.font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit().lineLimit(1).fixedSize()
                }
                if !cancelled { SessionUnitsPicker(course: course, session: session, compact: model.unitsInTitle(session, in: file)) }
            }
        }
        // Takes the room the fixed slots leave, so the topic and units truncate before anything else moves.
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(ahead ? 0.55 : 1)
        if !cancelled {
            HStack(spacing: Theme.Space.s) {
                if recordingThis {
                    Label(.sessionsRecording, systemImage: "waveform").foregroundStyle(Theme.Palette.danger)
                        .symbolEffect(.variableColor.iterative, isActive: recorder.state == .recording)
                } else if let last = recordings.last {
                    SessionSlot(model.recordingsLabel(recordings.count), symbol: "waveform", help: String(localized: .sessionsRecordingPlayHelp), fixed: false) { playing = last }
                } else if today && !recorder.isActive {
                    SessionSlot(String(localized: .sessionsRecordingShort), symbol: "record.circle", help: String(localized: .sessionsRecordHelp), fixed: false) {
                        model.record(session, locale: Locale(identifier: "ko-KR"))
                    }
                }
                // No empty recording slot: it sits leftmost, so the note slots line up without it and the topic keeps the room.
                SessionNoteSlots(file: file, session: session, offersRough: today, openNote: openNote, create: open)
            }
        }
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless).pointingHand()
        .fixedSize()
        .help(Text(.sessionsMenuHelp))
        .confirmationDialog(model.removeConfirmation(session, in: file), isPresented: $confirmingDelete) {
            Button(.sessionsRemove, role: .destructive) { model.remove(session) }
        } message: {
            Text(.sessionsRemoveMessage)
        }
        .alert(Text(.sessionsRemoveRefused), isPresented: Binding(get: { deleteRefusal != nil }, set: { if !$0 { deleteRefusal = nil } })) {
            Button(.commonOk, role: .cancel) {}
        } message: {
            Text(deleteRefusal ?? "")
        }
        .sheet(item: $playing) { RecordingPlayer(workspace: model.workspace, courseId: course.id, store: course.store, recording: $0, title: model.playerTitle(session, in: file)) }
    }

    @ViewBuilder var menuItems: some View {
        let recordings = model.recordings(of: session, in: course.file)
        let recorder = model.workspace.recorder
        let attendance = model.attendance(of: session, in: course.file)
        Button(String(localized: session.roughNoteId == nil ? .sessionsMakeRoughNote : .sessionsOpenRoughNote)) { open(.rough) }
        Button(String(localized: session.reviewNoteId == nil ? .sessionsMakeReviewNote : .sessionsOpenReviewNote)) { open(.review) }
        Toggle(String(localized: .sessionsSkipsReview), isOn: Binding(get: { session.skipsReview }, set: { model.setSkipsReview($0, of: session) }))
        // Also ahead of the class, for an absence known in advance; it counts toward the caps once the class starts.
        if model.takesAttendance(session) {
            Picker(String(localized: .sessionsAttendance), selection: Binding(get: { attendance }, set: { model.setAttendance($0, of: session) })) {
                ForEach(AttendanceState.steps, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
        Divider()
        Button(.sessionsRecordKorean) { model.record(session, locale: Locale(identifier: "ko-KR")) }.disabled(recorder.isActive)
        Button(.sessionsRecordEnglish) { model.record(session, locale: Locale(identifier: "en-US")) }.disabled(recorder.isActive)
        ForEach(Array(recordings.enumerated()), id: \.element.id) { i, r in
            Button(model.playLabel(i, r)) { playing = r }
        }
        Divider()
        Toggle(String(localized: .sessionsCancelled), isOn: Binding(get: { session.isCancelled }, set: { model.setCancelled($0, of: session) }))
        Divider()
        Button(.sessionsRemoveSessionEllipsis, role: .destructive) {
            deleteRefusal = model.removalRefusal(session)
            if deleteRefusal == nil { confirmingDelete = true }
        }
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

    func open(_ kind: NoteKind) {
        if let id = model.note(kind, of: session) { openNote(id) }
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
                SessionSlot(String(localized: .sessionsSlotRough), symbol: "doc.text", help: String(localized: .sessionsOpenRoughNote)) { openNote(id) }
            } else if offersRough {
                SessionSlot(String(localized: .sessionsSlotRough), symbol: "plus", tint: accent.ink, help: String(localized: .sessionsSlotRoughMakeHelp)) { create(.rough) }
            } else {
                SessionSlot.empty
            }
            if let id = session.reviewNoteId {
                // Made but not written yet: still in the missing note's warning color.
                if session.reviewNoteUnfinished {
                    SessionSlot(String(localized: .sessionsSlotReview), symbol: "square.and.pencil", tint: Theme.Palette.warning,
                                help: String(localized: .sessionsSlotReviewDraftHelp)) { openNote(id) }
                } else {
                    SessionSlot(String(localized: .sessionsSlotReview), symbol: "doc.text", help: String(localized: .sessionsOpenReviewNote)) { openNote(id) }
                }
            } else if file.needsReviewNote(session, at: .now) {
                SessionSlot(String(localized: .sessionsSlotReview), symbol: "plus", tint: Theme.Palette.warning, help: String(localized: .sessionsSlotReviewMakeHelp)) { create(.review) }
            } else if session.skipsReview {
                Text(.sessionsSlotNoReview).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: SessionSlot.width, alignment: .trailing)
            } else {
                SessionSlot.empty
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
