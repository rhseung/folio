import FolioDomain
import SwiftUI

enum CourseSection: CaseIterable, Identifiable {
    case overview, sessions, units, notes, materials
    case quizSolve, quizCards, quizStats, quizProblems
    case assignments, exams, grades
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: .courseSectionOverview)
        case .sessions: String(localized: .courseSectionSessions)
        case .units: String(localized: .courseSectionUnits)
        case .notes: String(localized: .courseSectionNotes)
        case .materials: String(localized: .courseSectionMaterials)
        case .quizSolve: String(localized: .courseSectionQuizSolve)
        case .quizCards: String(localized: .courseSectionQuizCards)
        case .quizStats: String(localized: .courseSectionQuizStats)
        case .quizProblems: String(localized: .courseSectionQuizProblems)
        case .assignments: String(localized: .courseSectionAssignments)
        case .exams: String(localized: .courseSectionExams)
        case .grades: String(localized: .courseSectionGrades)
        }
    }

    var tab: CourseTab {
        switch self {
        case .overview: .overview
        case .sessions, .units: .classes
        case .notes: .notes
        case .materials: .materials
        case .quizSolve, .quizCards, .quizStats, .quizProblems: .quiz
        case .assignments, .exams, .grades: .assessment
        }
    }
}

enum CourseTab: CaseIterable, Identifiable {
    case overview, classes, notes, materials, quiz, assessment
    var id: Self { self }

    var pages: [CourseSection] { CourseSection.allCases.filter { $0.tab == self } }

    var title: String {
        switch self {
        case .overview: String(localized: .courseTabOverview)
        case .classes: String(localized: .courseTabClasses)
        case .notes: String(localized: .courseTabNotes)
        case .materials: String(localized: .courseTabMaterials)
        case .quiz: String(localized: .courseTabQuiz)
        case .assessment: String(localized: .courseTabAssessment)
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .classes: "calendar"
        case .notes: "doc.text"
        case .materials: "folder"
        case .quiz: "questionmark.square"
        case .assessment: "checklist"
        }
    }
}

struct CourseView: View {
    @State private var model: CourseModel
    @State private var showClaude = false
    @State private var claudeWidth = Theme.Size.claudePanel
    @State private var pageReset = 0
    @State private var claudeDragBase: CGFloat?
    @Environment(\.searchTarget) private var searchTarget

    init(workspace: Workspace, courseID: UUID) {
        _model = State(initialValue: CourseModel(workspace: workspace, courseId: courseID))
    }

    func claude(_ course: LoadedCourse) -> some View {
        ClaudePanel(workspace: model.workspace, course: course, openNote: model.section == .notes ? model.openNote : nil, insertIntoNote: { model.noteInsert = $0 }) {
            model.show(note: $0)
        }
    }

    /// Past this the panel stops growing with the window: a full-height panel read as a sidebar laid over the page.
    static let claudeMaxHeight: CGFloat = 720

    func claudeFloat(_ course: LoadedCourse) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Space.m) {
            if showClaude {
                claude(course)
                    // Inside the glass, controls wash instead of standing on it as solid fills. Set inside
                    // `floatingGlass()`, which would otherwise draw a wash instead of the glass itself.
                    .environment(\.onGlass, true)
                    // At most this wide, narrower when the page is: a fixed width ran past a narrow page's edge.
                    .frame(maxWidth: claudeWidth, maxHeight: Self.claudeMaxHeight)
                    .floatingGlass()
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                    .overlay(alignment: .leading) { claudeResizeHandle }
                    .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }
            Button { showClaude.toggle() } label: {
                Image(systemName: showClaude ? "xmark" : "sparkle")
                    .font(Theme.Glyph.fab)
                    .foregroundStyle(showClaude ? Theme.Palette.textSecondary : model.accent.color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Theme.Size.fab, height: Theme.Size.fab)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.pointing(.plain))
            .help(String(localized: showClaude ? .courseClaudeClose : .courseClaudeAsk))
            .accessibilityLabel(showClaude ? String(localized: .courseClaudeClose) : "Claude")
        }
        .padding(Theme.Space.l)
    }

    var claudeResizeHandle: some View {
        Color.clear.frame(width: Theme.Space.s).contentShape(.rect)
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let base = claudeDragBase ?? claudeWidth
                    claudeDragBase = base
                    claudeWidth = min(640, max(300, base - drag.translation.width))
                }
                .onEnded { _ in claudeDragBase = nil })
    }

    var body: some View {
        if let course = model.course {
            let workspace = model.workspace
            HStack(spacing: 0) {
                CourseColumn(model: model, course: course)
                    .frame(width: Theme.Size.courseColumn)
                    // Back to the section's first screen from a file or unit opened in it.
                    .crumb(model.section.title, level: 1, symbol: model.section.tab.symbol) { pageReset += 1 }
                ColumnDivider()
                Group {
                    switch model.section {
                    case .overview: CourseOverview(model: model, course: course)
                    case .sessions: SessionsView(workspace: workspace, course: course) { model.show(note: $0) }
                    case .units: UnitsView(workspace: workspace, course: course)
                    case .notes: NotesView(workspace: workspace, course: course, selection: model.openNote, insert: $model.noteInsert) { model.openNote = $0 }
                    // One branch for every quiz page, so the quiz model and a pending solve request survive switching pages.
                    case .quizSolve, .quizCards, .quizStats, .quizProblems: QuizView(workspace: model.workspace, course: course, section: $model.section)
                    case .materials: MaterialsView(workspace: workspace, course: course)
                    case .assignments: AssignmentsView(workspace: workspace, course: course)
                    case .grades: CourseGradesView(workspace: workspace, course: course)
                    case .exams: ExamsView(workspace: workspace, course: course) { model.show(note: $0) }
                    }
                }
                // A new identity drops what the page opened (a file, a unit), which is all its section crumb asks for.
                .id(pageReset)
                // minWidth 0: a page's fixed-width rows must never set the column's minimum. When that minimum plus a
                // side column exceeds the window, AppKit loops on constraints and kills the app.
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .paperList()
                // Over the page, not beside it: a sidebar (or the iPad's inspector) squeezed the page to a strip in a
                // narrow window.
                .overlay(alignment: .bottomTrailing) { claudeFloat(course) }
            }
            .animation(.snappy(duration: 0.25), value: showClaude)
            .environment(\.accent, model.accent)
            .tint(model.accent.ink)
            .navigationTitle(course.title)
            .navigationSubtitle(model.section.title)
            .studyTime(course: model.courseId)
            .onChange(of: searchTarget.wrappedValue, initial: true) { _, target in
                if let target, model.follow(target) { searchTarget.wrappedValue = nil }
            }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.section, initial: true) { _, new in if let new { model.section = new } }
            .onChange(of: SnapshotDriver.shared.claudePanel, initial: true) { _, new in showClaude = new }
            #endif
        } else {
            ContentUnavailableView(String(localized: .courseNotFound), systemImage: "questionmark.folder")
        }
    }
}

struct CourseColumn: View {
    @Environment(\.accent) private var accent
    @Bindable var model: CourseModel
    let course: LoadedCourse

    var body: some View {
        let file = course.file
        let recent = model.recent(file)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
                // Code and name only; credits, grading and professors are on the overview page.
                // Laid out like a ColumnRow, the dot in the icon column, so the title and the rows below share their edges.
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.codeLine(model.workspace)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.leading, ColumnRow<EmptyView>.titleInset - Theme.Inset.listRow.leading)
                    HStack(spacing: ColumnRow<EmptyView>.gap) {
                        CourseMark(icon: course.file.course.icon, color: accent.color, font: Theme.Glyph.lineTitle)
                        Text(course.title).font(Theme.Typeface.columnTitle).lineLimit(2)
                    }
                }
                .padding(.horizontal, Theme.Inset.listRow.leading)

                VStack(spacing: Theme.Space.xxs) {
                    ForEach(CourseTab.allCases) { item in
                        let chosen = model.section.tab == item
                        Button { if !chosen { model.section = item.pages[0] } } label: {
                            ColumnRow(title: item.title, symbol: item.symbol, chosen: chosen, tint: accent.color, fill: accent.tint) {
                                if let trailing = model.trailing(item, file: file) {
                                    if trailing.warning {
                                        Chip(trailing.text, tone: .warning)
                                    } else {
                                        Text(trailing.text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.pointing(.plain))
                        if chosen, item.pages.count > 1 {
                            ForEach(item.pages) { page in
                                Button { model.section = page } label: {
                                    Text(page.title)
                                        .foregroundStyle(model.section == page ? accent.ink : Theme.Palette.textSecondary)
                                        .fontWeight(model.section == page ? .semibold : .regular)
                                        .padding(.leading, ColumnRow<EmptyView>.titleInset)
                                        .padding(.vertical, Theme.Space.xs)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                            }
                        }
                    }
                }

                if model.section == .notes {
                    NoteList(workspace: model.workspace, course: course, selection: $model.openNote)
                } else if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Caption(String(localized: .courseRecent)).padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.tight)
                        ForEach(recent) { session in
                            Button {
                                if let id = session.roughNoteId ?? session.reviewNoteId { model.show(note: id) } else { model.section = .sessions }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(model.recentTitle(session, in: file)).lineLimit(1)
                                    Text(model.recentDetail(session, in: file))
                                        .font(Theme.Typeface.label.weight(.regular))
                                        .foregroundStyle(file.needsReviewNote(session, at: .now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                                }
                                .padding(Theme.Inset.listRow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu { SessionMenu(courseId: course.id, sessionId: session.id, openNote: model.show(note:)) { model.section = .sessions } }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .background(Theme.Palette.window)
    }
}

struct CourseOverview: View {
    @Environment(\.accent) private var accent
    let model: CourseModel
    let course: LoadedCourse
    @State private var editing = false
    @State private var wide = true

    var body: some View {
        let file = course.file
        let now = Date.now
        let score = model.score(file)
        let reviews = model.reviews(now: now)
        let suggested = model.suggested(course, now: now)
        let unclassified = model.unclassified(file)
        // Two columns that each run as long as their own blocks; a grid row made the short week card as tall as the units.
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.xl)) : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xl))

        Page {
            PageHeader(title: course.title, subtitle: model.subtitle(file)) {
                let code = course.codeLine(model.workspace)
                if !code.isEmpty { Chip(code, tone: .accent) }
                Chip(model.credits(file.course))
                Chip(file.course.gradingMode.label)
                Spacer()
                Button(.courseEdit, systemImage: "slider.horizontal.3") { editing = true }.buttonStyle(.ghost)
            }
            .sheet(isPresented: $editing) { EditCourseSheet(course: course) }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.editCourse, initial: true) { _, on in editing = on }
            #endif

            StatStrip(items: model.stats(file, reviews: reviews, suggested: suggested, now: now))

            if !unclassified.isEmpty {
                NoticeCard(title: String(localized: .courseUnclassifiedNotice(unclassified.count)), detail: String(localized: .courseUnclassifiedDetail),
                           systemImage: "tray.fill") {
                    Button(.courseReviewMaterials) { model.section = .materials }.buttonStyle(.ghost)
                }
            }

            layout {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    weekBlock(file, suggested: suggested, now: now)
                    assignmentsBlock(file, now: now)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    unitsBlock(file, reviews: reviews)
                    gradesBlock(file, score: score)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onGeometryChange(for: Bool.self) { $0.size.width >= 620 } action: { wide = $0 }

            InfoBlocks(course: course)
        }
    }

    func weekBlock(_ file: CourseFile, suggested: Workspace.SuggestedSession?, now: Date) -> some View {
        let sessions = model.weekSessions(file, now: now)
        let next = model.weekSuggestion(suggested, now: now)
        return Block(String(localized: .courseThisWeek)) {
            if !sessions.isEmpty || next == nil {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .courseNoClassThisWeek)) } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) {
                            VStack(spacing: 0) {
                                Text(s.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
                                // The bare number: Korean's day format adds 일, which overflowed the 34pt column.
                                Text(verbatim: "\(model.day(of: s.date))").font(Theme.Typeface.figureMedium).foregroundStyle(s.date > now ? accent.ink : Theme.Palette.text)
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(model.recentTitle(s, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                    .strikethrough(s.isCancelled)
                                Text(model.weekStatus(s, in: file, now: now))
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(file.needsReviewNote(s, at: now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu { SessionMenu(courseId: course.id, sessionId: s.id, openNote: model.show(note:)) { model.section = .sessions } }
                    }
                }
                .opens { model.section = .sessions }
            }
            // The class the timetable says comes next, before it is made: starting its note makes it, as on Today.
            if let next { SuggestedSessionRow(item: next, openNote: model.show(note:)) }
        }
    }

    func assignmentsBlock(_ file: CourseFile, now: Date) -> some View {
        let open = model.openAssignments(file)
        let shown = Array(open.prefix(5))
        return Block(String(localized: .courseSectionAssignments), note: model.assignmentsNote(file)) {
            Card {
                if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: file.assignments.isEmpty ? .courseNoAssignments : .courseNoOpenAssignments)) } }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                    CardRow(last: i == shown.count - 1 && open.count == shown.count) {
                        Image(systemName: a.status.symbol).foregroundStyle(a.status.tint)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(a.due?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? String(localized: .courseNoDue))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                        }
                        Spacer(minLength: Theme.Space.s)
                        if let due = a.due {
                            if due < now {
                                Chip(String(localized: .courseOverdue), tone: .danger)
                            } else {
                                DdayChip(days: model.days(to: due))
                            }
                        }
                    }
                    .contextMenu { Button(.courseShowAssignments, systemImage: "checklist") { model.section = .assignments } }
                }
                if open.count > shown.count {
                    CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(open.count - shown.count))) }
                }
            }
            .opens { model.section = .assignments }
        }
    }

    func unitsBlock(_ file: CourseFile, reviews: [Workspace.ReviewEntry]) -> some View {
        let shown = model.glanceUnits(file, reviews: reviews)
        return Block(String(localized: .courseSectionUnits), note: file.units.count > shown.count ? String(localized: .courseUnitsNote(file.units.count, shown.count)) : nil) {
            Card {
                if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: file.units.isEmpty ? .courseNoUnits : .courseNoCoveredUnits)) } }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                    let entry = reviews.first { $0.item.unitId == unit.id }
                    ReviewOpener(courseId: course.id, unitId: unit.id) {
                        CardRow(last: i == shown.count - 1) {
                            Text(unit.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            if let entry {
                                Chip(String(localized: entry.item.overdueDays > 0 ? .unitsDaysLate(entry.item.overdueDays) : .courseReviewToday),
                                     tone: entry.item.overdueDays > 0 ? .danger : .accent)
                            } else {
                                Text(.sessionsCount(unit.sessionIds.count)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                    .contextMenu {
                        Button(.courseShowUnits, systemImage: "list.bullet") { model.section = .units }
                        if entry != nil {
                            Button(.courseSkipReviewToday, systemImage: "forward") { model.skipReview(unit) }
                        }
                    }
                }
            }
            .opens { model.section = .units }
        }
    }

    func gradesBlock(_ file: CourseFile, score: GradeCalculator.CourseScore) -> some View {
        Block(String(localized: .courseSectionGrades), note: file.components.isEmpty ? nil : String(localized: .courseRemainingWeight(Int(score.remainingWeight.rounded())))) {
            Card(padding: Theme.Space.l) {
                if file.components.isEmpty {
                    EmptyLine(String(localized: .courseNoComponents))
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                            Figure(String(localized: .courseSecured), score.secured.oneDecimal, font: Theme.Typeface.figureCompact)
                            Figure(String(localized: .courseProjectedTitle), score.projected.map(\.oneDecimal) ?? "-", tint: accent.ink, font: Theme.Typeface.figureCompact)
                        }
                        .sensitive()
                        // Names live in the segment tooltips and on the grades page; listed here they swamp the card.
                        WeightBar(components: file.components)
                    }
                }
            }
            .opens { model.section = .grades }
        }
    }
}

struct SessionMenu: View {
    @Environment(Workspace.self) private var workspace
    let courseId: UUID
    let sessionId: UUID
    let openNote: (UUID) -> Void
    let showSessions: () -> Void

    var body: some View {
        Button(.sessionsOpenRoughNote, systemImage: "pencil.line") { if let id = workspace.note(.rough, of: sessionId, in: courseId) { openNote(id) } }
        Button(.sessionsOpenReviewNote, systemImage: "square.and.pencil") { if let id = workspace.note(.review, of: sessionId, in: courseId) { openNote(id) } }
        if let session = workspace.course(courseId)?.file.sessions.first(where: { $0.id == sessionId }), session.reviewNoteId != nil {
            if session.reviewNoteUnfinished {
                Button(.courseReviewNoteFinish, systemImage: "checkmark.circle") { workspace.setReviewNoteUnfinished(false, of: sessionId, in: courseId) }
            } else {
                Button(.courseReviewNoteReopen, systemImage: "arrow.uturn.backward") { workspace.setReviewNoteUnfinished(true, of: sessionId, in: courseId) }
            }
        }
        Button(.courseShowSessions, systemImage: "calendar", action: showSessions)
    }
}

struct WeightBar: View {
    @Environment(\.accent) private var accent
    let components: [GradeComponent]

    var body: some View {
        let sorted = components.sorted { $0.order < $1.order }
        GeometryReader { proxy in
            let total = max(sorted.map(\.weight).reduce(0, +), 1)
            HStack(spacing: Theme.Space.xxs) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, c in
                    accent.color.opacity(max(0.15, 1 - Double(i) * 0.2))
                        .frame(width: max(0, proxy.size.width * c.weight / total - 2))
                        .help("\(c.name) \(c.weight.formatted())%")
                }
            }
        }
        .frame(height: 10)
        .clipShape(.capsule)
    }
}


@MainActor
extension LoadedCourse {
    func codeLine(_ workspace: Workspace) -> String {
        let c = file.course
        // `GS2004-02`: the prefix, the course number and the section, written once.
        let prefix = c.codes.first.flatMap { id in workspace.catalog.codes.first { $0.id == id }?.prefix } ?? ""
        return prefix + c.number
    }

    func factChips(_ workspace: Workspace) -> [String] {
        let c = file.course
        let professors = c.instructorIds.compactMap { id in workspace.catalog.people.first { $0.id == id }?.name }
        return [String(localized: .courseCredits(c.credits.formatted())), c.gradingMode.label] + professors
    }
}

extension GradingMode {
    var label: String {
        switch self {
        case .relative: String(localized: .gradingModeRelative)
        case .absolute: String(localized: .gradingModeAbsolute)
        case .passFail: "S/U"
        }
    }
}
