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
            if !model.untouched.isEmpty { untouchedCard }
            ForEach(model.weeks(file)) { week in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    header(week)
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(week.rows) { row in self.row(row, file: file) }
                    }
                }
            }
        }
        .sheet(isPresented: $editingTimes) { ClassTimesSheet(workspace: model.workspace, course: course) }
        .sheet(isPresented: $adding) { SessionFormSheet(workspace: model.workspace, course: course) }
        .task(id: file.sessions) { model.loadUntouched(course) }
        .confirming($model.pending)
    }

    func header(_ week: SessionsModel.Week) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(.sessionsWeek(week.number)).font(Theme.Typeface.sectionTitle)
                .foregroundStyle(week.thisWeek ? accent.ink : Theme.Palette.textSecondary)
            if week.thisWeek { Chip(String(localized: .sessionsThisWeek), tone: .accent) }
            Text(week.range).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            if week.examWeek {
                Text("· " + String(localized: .sessionsExamWeek)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder func row(_ row: SessionsModel.TimelineRow, file: CourseFile) -> some View {
        switch row.item {
        case .week, .month:
            EmptyView()
        case .exam(let exam, let date):
            ExamMarkerRow(model: model, exam: exam, date: date)
        case .session(let session, let exams):
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                SessionCard(model: model, course: course, session: session, now: model.workspace.now, openNote: openNote)
                    .modifier(ClassExamCard(model: model, exams: exams, now: model.workspace.now))
            }
            .fileDrop { model.importFiles($0, into: session) }
        case .planned(_, let exams):
            if let item = row.planned {
                PlannedSessionCard(model: model, item: item, openNote: openNote, editTimes: { editingTimes = true })
                    .modifier(ClassExamCard(model: model, exams: exams, now: model.workspace.now))
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
                    Text(course.file.name(of: s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if model.untouchedMore > 0 {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(model.untouchedMore))) }
            }
        }
    }
}

/// The parts every class card shares: the date tile, the frame, and the ⋯ button.
enum ClassCard {
    static let tile: CGFloat = 44
    static let menu: CGFloat = 28
    static let radius = Theme.Radius.card

    struct Tile: View {
        let month: String
        let day: String
        var ink: Color = Theme.Palette.text
        var monthInk: Color = Theme.Palette.textTertiary
        var fill: Color = Theme.Palette.page
        var dashed = false

        var body: some View {
            VStack(spacing: 0) {
                Text(month).font(Theme.Typeface.label).foregroundStyle(monthInk)
                Text(day).font(Theme.Typeface.figureSmall.weight(.bold)).foregroundStyle(ink)
            }
            .frame(width: ClassCard.tile, height: ClassCard.tile)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
    }

    /// The capsule a card's trailing row is made of. A state nothing opens (recording now, minutes left) is a bare tag,
    /// and `Pill` wraps the same tag in a button, so the row keeps one height and font whichever it holds.
    struct Tag: View {
        @Environment(\.accent) private var accent
        let title: String
        var symbol: String?
        var tone: Tone = .plain

        var body: some View {
            HStack(spacing: Theme.Space.xs) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            // Fixed-width digits so a countdown ticking each minute doesn't jiggle the row.
            .font(Theme.Typeface.label.monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 24)
            .background(fill, in: .capsule)
            .fixedSize()
        }

        private var foreground: Color {
            switch tone {
            case .plain: Theme.Palette.textSecondary
            case .accent: accent.ink
            default: tone.foreground
            }
        }

        private var fill: Color {
            switch tone {
            case .accent: accent.tint
            case .success: Theme.Palette.success.opacity(Theme.Opacity.tint)
            default: tone.fill
            }
        }
    }

    struct Pill: View {
        let title: String
        var symbol: String?
        var tone: Tone = .plain
        var help: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Tag(title: title, symbol: symbol, tone: tone).contentShape(.capsule)
            }
            .buttonStyle(.pointing(.plain))
            .fixedSize()
            .help(help)
        }
    }

    struct MenuButton<Items: View>: View {
        let help: String
        @ViewBuilder var items: Items

        var body: some View {
            Menu { items } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: ClassCard.menu, height: ClassCard.menu).contentShape(.circle)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(help))
        }
    }
}

/// A class the schedule still holds, not saved: an empty dashed slot. Its menu makes the session first, so a 휴강 or an
/// absence known weeks ahead has something to hang on; on its day it offers the same one-click start a session does.
struct PlannedSessionCard: View {
    @Environment(\.accent) private var accent
    @Environment(Workspace.self) private var workspace
    let model: SessionsModel
    let item: Workspace.SuggestedSession
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let date = item.suggestion.date
        let today = workspace.isStudyToday(date)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ClassCard.Tile(month: model.month(date), day: model.day(date), fill: .clear, dashed: true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(.sessionsClass).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    HStack(spacing: Theme.Space.tight) {
                        Text(model.plannedLine(item)).monospacedDigit().lineLimit(1)
                        if item.suggestion.link != nil {
                            Image(systemName: "video").help(Text(.sessionsOnline))
                        }
                    }
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClassCard.MenuButton(help: String(localized: .sessionsSuggestionMenuHelp)) {
                    SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes)
                }
            }
            if today {
                HStack(spacing: Theme.Space.s) {
                    if let link = item.suggestion.link.flatMap(OnlineLink.url) { JoinOnlineButton(url: link, prominent: true) }
                    Button(.sessionsRecord, systemImage: "record.circle") { model.menu.record(item) }
                        .buttonStyle(.pointing(.bordered)).disabled(model.menu.isRecording)
                    Button(.sessionsRoughNote, systemImage: "doc.text") { if let id = model.menu.roughNote(item) { openNote(id) } }
                        .buttonStyle(.pointing(.bordered)).help(Text(.sessionsRoughNoteHelp))
                }
                .padding(.leading, ClassCard.tile + Theme.Space.l)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 60)
        // Half the card's white over the page, but opaque, so an exam card tucked in behind doesn't show through.
        .background(Theme.Palette.card.opacity(Theme.Opacity.planned), in: .rect(cornerRadius: ClassCard.radius))
        .background(Theme.Palette.page, in: .rect(cornerRadius: ClassCard.radius))
        .overlay {
            RoundedRectangle(cornerRadius: ClassCard.radius).strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
        .help(Text(.sessionsPlannedHelp))
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
                CourseMark(workspace, item.courseId)
                // Today's own list: the day goes without saying.
                Text(workspace.course(item.courseId)?.title ?? "").lineLimit(1)
                    .help(Text(.sessionsSuggested))
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                    Text(date.formatted(.dateTime.weekday()) + " " + TimeMenu.label(workspace.calendar.component(.hour, from: date) * 60 + workspace.calendar.component(.minute, from: date))).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
                .frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(.sessionsLecture).font(Theme.Typeface.bodyStrong)
                    // The day is beside it already.
                    if !item.suggestion.room.isEmpty {
                        Text(item.suggestion.room).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: Theme.Space.m)
            if today, let link = item.suggestion.link.flatMap(OnlineLink.url) { JoinOnlineButton(url: link).fixedSize() }
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
        let model = SessionMenuModel(workspace: workspace, courseId: item.courseId)
        HStack(spacing: Theme.Space.s) {
            if model.isToday(item) {
                Button { if let id = model.roughNote(item) { openNote(id) } } label: {
                    if compact { Image(systemName: "square.and.pencil").accessibilityLabel(Text(.sessionsRoughNote)) } else { Text(.sessionsRoughNote) }
                }
                .buttonStyle(.pointing(.borderedProminent))
                .help(Text(.sessionsRoughNoteHelp))
            } else {
                Button(.sessionsMake) { model.make(item) }.buttonStyle(.pointing(.bordered))
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

/// Adds a session, or edits one when given: off-timetable classes (a makeup, a recitation) need their own end, and an
/// online one its meeting link.
struct SessionFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionFormModel

    init(workspace: Workspace, course: LoadedCourse, session: Session? = nil) {
        _model = State(initialValue: SessionFormModel(workspace: workspace, courseId: course.id, session: session))
    }

    var body: some View {
        SheetForm(title: model.title, confirm: model.confirm, disabled: model.disabled, note: model.note) {
            FormRow(label: String(localized: .sessionsDate)) { DateChip(date: Binding(get: { model.start }, set: { model.setStart($0) })) }
            FormRow(label: String(localized: .sessionsEnd)) { TimeMenu(minute: Binding(get: { model.endMinute }, set: { model.setEnd($0) })) }
            FormRow(label: String(localized: .sessionsTopic), detail: String(localized: .sessionsTopicDetail)) {
                InlineField(String(localized: .sessionsTopicPrompt), text: $model.topic)
            }
            FormRow(label: String(localized: .sessionsLink), detail: String(localized: .sessionsLinkDetail), last: model.session != nil) {
                InlineField(String(localized: .sessionsLinkPrompt), text: $model.link)
            }
            if model.session == nil {
                FormRow(label: String(localized: .sessionsCancelled), last: true) { Switch(isOn: $model.cancelled) }
            }
        } onConfirm: {
            model.submit()
            dismiss()
        }
    }
}

/// Joins an online class: Zoom links go to the Zoom app directly, and anything else (or Zoom when the app isn't
/// installed) opens in the browser.
struct JoinOnlineButton: View {
    @Environment(\.openURL) private var openURL
    let url: URL
    /// The class card's own start button, rather than a slot among the notes.
    var prominent = false

    var body: some View {
        if prominent {
            Button(.sessionsJoin, systemImage: "video") { Self.join(url, openURL) }.buttonStyle(.pointing(.borderedProminent))
                .help(url.absoluteString)
        } else {
            SessionSlot(String(localized: .sessionsJoin), symbol: "video", help: url.absoluteString, fixed: false) { Self.join(url, openURL) }
        }
    }

    static func join(_ url: URL, _ openURL: OpenURLAction) {
        guard let app = OnlineLink.appURL(url) else { return openURL(url) }
        openURL(app) { accepted in if !accepted { openURL(url) } }
    }
}

/// The units a session covers, linked or unlinked in place. A held class with none is flagged, since its review
/// never reaches the unit queue.
struct SessionUnitsPicker: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let session: Session
    /// The icon alone, when the row's title already names the units.
    var compact = false
    /// After other text on a line, so it leads with a `·`; a held class with none asks for them in the accent.
    var separated = false

    var body: some View {
        let file = course.file
        let linked = file.units(of: session)
        let shown = UnitTree.deepest(linked, in: file.units)
        let missing = file.needsUnits(session, at: workspace.now)
        if !file.units.isEmpty && (!linked.isEmpty || !session.skipsReview) {
            SearchPicker(options: UnitTree.outline(file.units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) },
                         isSelected: { id in linked.contains { $0.id == id } },
                         pick: { id in SessionMenuModel(workspace: workspace, courseId: course.id).toggleUnit(id, of: session) },
                         multiple: true, prompt: String(localized: .sessionsUnitsSearch), flexible: true) {
                if separated {
                    inline(shown: shown, missing: missing)
                } else {
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
            }
            // The label truncates on a narrow row, so the tooltip carries every title.
            .help(missing ? String(localized: .sessionsUnitsMissingHelp) : shown.isEmpty ? String(localized: .sessionsUnitsHelp) : shown.map(\.title).joined(separator: "\n"))
        }
    }

    @ViewBuilder func inline(shown: [FolioDomain.Unit], missing: Bool) -> some View {
        HStack(spacing: Theme.Space.tight) {
            // The title names the units already, so only the icon is left to click and it needs no separator.
            if !(compact && !shown.isEmpty) { Text("·") }
            if !shown.isEmpty {
                if !compact { Text(shown.map(\.title).joined(separator: " · ")).lineLimit(1).truncationMode(.tail) } else { Image(systemName: "link") }
            } else if missing {
                Label(.sessionsUnitsAdd, systemImage: "plus").labelStyle(.titleAndIcon).fontWeight(.semibold).foregroundStyle(accent.ink)
            } else {
                Label(.sessionsUnitsAdd, systemImage: "plus").labelStyle(.titleAndIcon)
            }
        }
        .contentShape(.rect)
    }
}

/// An exam outside class time, at its own date: in red whether taken or not, with how far off while it is ahead.
/// A score is a grade and stays on the grades page.
struct ExamMarkerRow: View {
    let model: SessionsModel
    let exam: Exam
    let date: Date

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            ClassCard.Tile(month: model.month(date), day: model.day(date), ink: Theme.Palette.danger, monthInk: Theme.Palette.danger,
                           fill: Theme.Palette.danger.opacity(Theme.Opacity.tint))
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold))
                Text(exam.title).font(Theme.Typeface.bodyLarge.weight(.bold)).lineLimit(1).fixedSize()
                Text(model.examLine(exam, date)).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                Capsule().fill(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge)).frame(minWidth: Theme.Space.xl, maxWidth: .infinity).frame(height: 2)
                if let days = model.examDays(exam, now: model.workspace.now) {
                    Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true)
                }
            }
            .foregroundStyle(Theme.Palette.danger)
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 52)
    }
}

/// Exams held in the class's time, as a card tucked in behind the class with only its top line showing. The class
/// stays the row: the exam is something that happens in it.
struct ClassExamCard: ViewModifier {
    let model: SessionsModel
    let exams: [Exam]
    let now: Date
    /// How far the card runs on under the class, so it reads as behind it rather than above it.
    static let tuck: CGFloat = 8

    func body(content: Content) -> some View {
        if exams.isEmpty {
            content
        } else {
            VStack(spacing: 0) {
                card
                content
                    // On the class's own shape, so its text casts none.
                    .background { RoundedRectangle(cornerRadius: ClassCard.radius).fill(.clear).shadow(color: .black.opacity(0.06), radius: 3, y: -2) }
                    .padding(.top, -Self.tuck)
            }
            // Room above, so a tucked-in exam reads as its own class's and not the one before.
            .padding(.top, Theme.Space.s)
        }
    }

    var card: some View {
        VStack(spacing: Theme.Space.xxs) {
            ForEach(exams) { exam in
                HStack(spacing: Theme.Space.l) {
                    Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold)).frame(width: ClassCard.tile)
                    HStack(spacing: Theme.Space.s) {
                        Text(exam.title).font(Theme.Typeface.bodyStrong.weight(.bold)).lineLimit(1).fixedSize()
                        if let time = model.examTime(exam) {
                            Text(time).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let days = model.examDays(exam, now: now) { Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true) }
                }
                .frame(minHeight: 24)
            }
        }
        .foregroundStyle(Theme.Palette.danger)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s + Self.tuck)
        .padding(.leading, Theme.Space.xs)
        .padding(.trailing, ClassCard.tile)
        .background(Theme.Palette.dangerFill, in: .rect(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius)
                .strokeBorder(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge), lineWidth: 1)
        }
        // Narrower than the class, as a card further back would be.
        .padding(.horizontal, Theme.Space.m)
    }
}

/// A saved class: the date tile, what it covered and its attendance, then its recording and review note as pills.
/// Under way it fills from the left as the class goes; on its day it offers joining, recording and the rough note in
/// one click. Everything else lives in the ⋯ menu.
struct SessionCard: View {
    @Environment(\.accent) private var accent
    let model: SessionsModel
    let course: LoadedCourse
    let session: Session
    var now = Date.now
    let openNote: (UUID) -> Void
    @State private var playing: Recording?
    @State private var editing = false

    var body: some View {
        let file = course.file
        let expected = session.expectedEnd(schedule: file.course.schedule, classMinutes: model.workspace.settings.classMinutes, calendar: model.calendar)
        let live = model.isOngoing(session, end: expected, now: now)
        let progress = model.progress(session, end: expected, now: now)
        let cancelled = session.isCancelled
        let starts = !cancelled && model.offersJoin(session, in: file, now: now)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ClassCard.Tile(month: model.month(session.date), day: model.day(session.date),
                               ink: live ? accent.ink : Theme.Palette.text, monthInk: live ? accent.ink : Theme.Palette.textTertiary,
                               fill: live ? accent.tint : Theme.Palette.page)
                    .opacity(cancelled ? Theme.Opacity.ended : 1)
                lines(file, live: live).opacity(cancelled ? Theme.Opacity.ended : 1)
                trailing(file, live: live, expected: expected).opacity(cancelled ? Theme.Opacity.ended : 1)
                ClassCard.MenuButton(help: String(localized: .sessionsMenuHelp)) { menuItems }
            }
            if starts { actions(file) }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 60)
        .background {
            // The class's elapsed share fills the card from the left with a hard edge, standing in for a progress bar.
            GeometryReader { proxy in
                Theme.Palette.card.overlay(alignment: .leading) {
                    if let progress { accent.tint.frame(width: proxy.size.width * progress) }
                }
            }
            .clipShape(.rect(cornerRadius: ClassCard.radius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ClassCard.radius).strokeBorder(live ? accent.color.opacity(Theme.Opacity.liveEdge) : Theme.Palette.line, lineWidth: 1)
        }
        .contentShape(.rect)
        .contextMenu { menuItems }
        .sheet(item: $playing) { RecordingPlayer(workspace: model.workspace, courseId: course.id, store: course.store, recording: $0, title: model.playerTitle(session, in: file)) }
        .sheet(isPresented: $editing) { SessionFormSheet(workspace: model.workspace, course: course, session: session) }
    }

    func lines(_ file: CourseFile, live: Bool) -> some View {
        let late = model.lateMark(session, in: file)
        let cancelled = session.isCancelled
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(model.title(of: session, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(model.hasSubject(session, in: file) ? Theme.Palette.text : Theme.Palette.textTertiary)
                    .help(file.title(of: session, calendar: model.calendar))
                if live { Chip(String(localized: .sessionsNow), tone: .accent) }
                if cancelled { Chip(String(localized: .sessionsCancelled)) }
                if let late { Chip(late.label, tone: late.value == .late ? .warning : late.value == .absent ? .danger : .plain) }
            }
            HStack(spacing: Theme.Space.tight) {
                Text(model.dayLine(session.date, end: model.end(of: session, in: file))).monospacedDigit().lineLimit(1).fixedSize()
                if model.link(of: session, in: file) != nil && !cancelled {
                    Image(systemName: "video").help(Text(.sessionsOnline))
                }
                if !cancelled { SessionUnitsPicker(course: course, session: session, compact: model.unitsInTitle(session, in: file), separated: true) }
            }
            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
        // Takes the room the pills leave, so the title and units truncate before anything else moves.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func trailing(_ file: CourseFile, live: Bool, expected: Date) -> some View {
        let recordings = model.menu.recordings(of: session)
        let recorder = model.workspace.recorder
        HStack(spacing: Theme.Space.s) {
            if recordings.contains(where: { $0.id == recorder.current }) {
                ClassCard.Tag(title: String(localized: .sessionsRecording), symbol: "waveform", tone: .danger)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.state == .recording)
            } else if let last = recordings.last {
                ClassCard.Pill(title: model.recordingsLabel(recordings.count), symbol: "waveform", help: String(localized: .sessionsRecordingPlayHelp)) { playing = last }
            }
            switch model.review(of: session, in: file, now: now) {
            case .done(let id):
                ClassCard.Pill(title: String(localized: .sessionsReviewDone), tone: .success, help: String(localized: .sessionsOpenReviewNote)) { openNote(id) }
            case .writing(let id):
                ClassCard.Pill(title: String(localized: .sessionsReviewWriting), tone: .warning, help: String(localized: .sessionsSlotReviewDraftHelp)) { openNote(id) }
            // Not owed until the class ends: under way, the card's own buttons start the notes.
            case .missing where !live:
                ClassCard.Pill(title: String(localized: .sessionsReviewMissing), tone: .danger, help: String(localized: .sessionsSlotReviewMakeHelp)) { open(.review) }
            case .missing, nil:
                EmptyView()
            }
            if live {
                ClassCard.Tag(title: model.minutesLeft(until: expected, now: now), tone: .accent)
            }
        }
    }

    /// On the class's day: joining, recording and the rough note, a click each.
    func actions(_ file: CourseFile) -> some View {
        let recorder = model.workspace.recorder
        return HStack(spacing: Theme.Space.s) {
            if let link = model.link(of: session, in: file) { JoinOnlineButton(url: link, prominent: true) }
            if !recorder.isActive {
                Button(.sessionsRecord, systemImage: "record.circle") { model.menu.record(session) }.buttonStyle(.pointing(.bordered))
                    .help(Text(.sessionsRecordHelp))
            }
            Button(String(localized: session.roughNoteId == nil ? .sessionsRoughNote : .sessionsOpenRoughNote), systemImage: "doc.text") { open(.rough) }
                .buttonStyle(.pointing(.bordered))
        }
        .padding(.leading, ClassCard.tile + Theme.Space.l)
    }

    var menuItems: some View {
        SessionMenu(courseId: course.id, sessionId: session.id, openNote: openNote, play: { playing = $0 }, edit: { editing = true }) {
            model.remove(session)
        }
    }

    func open(_ kind: NoteKind) {
        if let id = model.menu.note(kind, of: session) { openNote(id) }
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
    @Environment(Workspace.self) private var workspace
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
            } else if file.needsReviewNote(session, at: workspace.now) {
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
