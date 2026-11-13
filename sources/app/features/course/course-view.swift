import FolioAI
import FolioDomain
import SwiftUI

struct CourseView: View {
    @State private var model: CourseModel
    @State private var pageReset = 0
    @Environment(\.paneInsert) private var paneInsert
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink
    @Environment(\.paneFocused) private var paneFocused

    init(workspace: Workspace, courseID: UUID) {
        _model = State(initialValue: CourseModel(workspace: workspace, courseId: courseID))
    }

    var body: some View {
        if let course = model.course {
            let workspace = model.workspace
            ColumnSplit(kind: .courseSections) {
                CourseColumn(model: model, course: course)
            } content: {
                Group {
                    switch model.section {
                    case .overview: CourseOverview(model: model, course: course)
                    case .sessions:
                        if let recording = model.openRecording {
                            RecordingPage(
                                workspace: workspace, course: course, recording: recording, place: model.place, moved: model.moved
                            )
                            .id(recording.id)
                        } else {
                            SessionsView(workspace: workspace, course: course)
                        }
                    case .units:
                        UnitsView(workspace: workspace, course: course, place: model.place) { id in
                            model.openUnit = id
                            model.moved(id.map { AppLink(.unit, $0) })
                        }
                    case .notes: CourseNotesPage(model: model, course: course)
                    // 퀴즈 페이지를 옮겨 다녀도 퀴즈 모델과 대기 중인 풀기 요청이 남도록, 모든 퀴즈 페이지를 한 갈래로
                    // 둔다.
                    case .quizSolve, .quizCards, .quizStats, .quizProblems:
                        QuizView(workspace: model.workspace, course: course, section: $model.section)
                    case .materials: MaterialsView(workspace: workspace, course: course, place: model.place, moved: model.moved)
                    case .assignments: AssignmentsView(workspace: workspace, course: course)
                    case .grades: CourseGradesView(workspace: workspace, course: course)
                    case .exams: ExamsView(workspace: workspace, course: course)
                    }
                }
                .environment(\.linkFocus, model.focus)
                // identity를 새로 주면 페이지가 연 파일이나 단원이 닫힌다. 구역 crumb이 바라는 동작은 그것뿐이다.
                .id(pageReset)
                .paperList()
            }
            // 열이 아니라 split에 단다. 접으면 열은 사라지지만 구역은 여전히 위치 표시의 맨 앞에 있어야 한다.
            .crumb(model.section.title, level: 1, symbol: model.section.tab.symbol) {
                model.resetPage()
                pageReset += 1
            }
            .courseAccent(model.accent)
            .navigationTitle(course.title)
            .navigationSubtitle(model.section.title)
            .studyTime(course: model.courseId)
            .onChange(of: place, initial: true) { _, entry in if let entry { model.follow(entry) } }
            .onChange(of: model.place) { _, link in openLink(link, course: model.courseId) }
            .onChange(of: paneInsert?.text) { _, text in
                guard let text else { return }
                model.noteInsert = text
                paneInsert?.text = nil
            }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.section, initial: true) { _, new in if let new, paneFocused { model.section = new } }
            #endif
        } else {
            ContentUnavailableView(String(localized: .courseNotFound), systemImage: "questionmark.folder")
        }
    }
}

struct CourseColumn: View {
    @Environment(\.accent) private var accent
    @Environment(\.closeColumn) private var closeColumn
    @Bindable var model: CourseModel
    let course: LoadedCourse

    var body: some View {
        let file = course.file
        let recent = model.recent(file)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.codeLine(model.workspace)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
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
                        Button {
                            if !chosen { model.section = item.pages[0] }
                            closeColumn()
                        } label: {
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
                                Button {
                                    model.section = page
                                    closeColumn()
                                } label: {
                                    Text(page.title).lineLimit(1)
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
                    NoteList(workspace: model.workspace, course: course, selection: $model.openNote, moves: model.noteMoves)
                } else if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Caption(String(localized: .courseRecent)).padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.tight)
                        ForEach(recent) { session in
                            Button {
                                if let id = session.roughNoteId ?? session.reviewNoteId {
                                    model.show(note: id)
                                } else {
                                    model.section = .sessions
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(model.recentTitle(session, in: file)).lineLimit(1)
                                    Text(model.recentDetail(session, in: file)).lineLimit(1)
                                        .font(Theme.Typeface.label.weight(.regular))
                                        .foregroundStyle(
                                            file.needsReviewNote(session, at: model.workspace.now)
                                                ? Theme.Palette.danger : Theme.Palette.textTertiary)
                                }
                                .padding(Theme.Inset.listRow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu { SessionMenu(courseId: course.id, sessionId: session.id, openNote: model.show(note:)) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
            .clearOfColumnButtons(inset: Theme.Space.l)
        }
        .overflowFade(.vertical)
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .columnBackground()
    }
}

struct CourseNotesPage: View {
    @Bindable var model: CourseModel
    let course: LoadedCourse
    @Environment(\.columnFolded) private var folded

    var body: some View {
        if folded, model.openNote == nil {
            ScrollView {
                NoteList(workspace: model.workspace, course: course, selection: $model.openNote, moves: model.noteMoves)
                    .padding(.horizontal, Theme.Inset.panel)
                    .padding(.vertical, Theme.Space.l)
                    .clearOfColumnButtons(inset: Theme.Space.l)
            }
            .overflowFade(.vertical)
        } else {
            NotesView(
                workspace: model.workspace, course: course, selection: model.openNote, anchor: model.noteAnchor, insert: $model.noteInsert,
                moves: model.noteMoves)
        }
    }
}

struct CourseOverview: View {
    @Environment(\.accent) private var accent
    @Bindable var model: CourseModel
    let course: LoadedCourse
    @State private var editing = false
    @State private var wide = true

    var body: some View {
        let file = course.file
        let now = model.workspace.now
        let score = model.score(file)
        let reviews = model.reviews(now: now)
        let suggested = model.suggested(course, now: now)
        let unclassified = model.unclassified(file)
        let layout =
            wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.xl))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xl))

        Page {
            PageHeader(title: course.title, subtitle: model.subtitle(file)) {
                let code = course.codeLine(model.workspace)
                if !code.isEmpty { Chip(code, tone: .accent) }
                Chip(model.credits(file.course))
                Chip(file.course.gradingMode.label)
                Spacer()
                Button(.courseEdit, systemImage: "slider.horizontal.3") { editing = true }.buttonStyle(.ghost)
                PageMenuButton { CourseMenu(courseId: course.id, host: .own) }
            }
            .sheet(isPresented: $editing) { EditCourseSheet(workspace: model.workspace, course: course) }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.editCourse, initial: true) { _, on in editing = on }
            #endif

            StatStrip(items: model.stats(file, reviews: reviews, suggested: suggested, now: now))

            if !unclassified.isEmpty {
                NoticeCard(
                    title: String(localized: .courseUnclassifiedNotice(unclassified.count)),
                    detail: String(localized: .courseUnclassifiedDetail),
                    systemImage: "tray.fill"
                ) {
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
            .onGeometryChange(for: Bool.self) {
                $0.size.width >= 620
            } action: {
                wide = $0
            }

            InfoBlocks(workspace: model.workspace, course: course)
        }
        .confirming($model.pending)
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
                                Text(s.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.Typeface.label.weight(.regular))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                // 숫자만 쓴다. 한국어 날짜 형식은 `일`을 붙여 34pt 열을 넘었다.
                                Text(verbatim: "\(model.day(of: s.date))").font(Theme.Typeface.figureMedium).foregroundStyle(
                                    s.date > now ? accent.ink : Theme.Palette.text)
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                HStack(spacing: Theme.Space.s) {
                                    Text(model.recentTitle(s, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                        .strikethrough(s.isCancelled)
                                    if s.kind == .makeup { SessionKindChip(kind: s.kind) }
                                }
                                Text(model.weekStatus(s, in: file, now: now)).lineLimit(1)
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(file.needsReviewNote(s, at: now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu { SessionMenu(courseId: course.id, sessionId: s.id, openNote: model.show(note:)) }
                    }
                }
                .opens { model.section = .sessions }
            }
            if let next { SuggestedSessionRow(item: next, openNote: model.show(note:)) }
        }
    }

    func assignmentsBlock(_ file: CourseFile, now: Date) -> some View {
        let open = model.openAssignments(file)
        let shown = Array(open.prefix(5))
        return Block(String(localized: .courseSectionAssignments), note: model.assignmentsNote(file)) {
            Card {
                if shown.isEmpty {
                    CardRow(last: true) {
                        EmptyLine(String(localized: file.assignments.isEmpty ? .courseNoAssignments : .courseNoOpenAssignments))
                    }
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                    CardRow(last: i == shown.count - 1 && open.count == shown.count) {
                        AssignmentStatusIcon(status: a.status)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(a.due?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? String(localized: .courseNoDue))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit().lineLimit(1)
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
                    .contextMenu { AssignmentMenu(courseId: course.id, assignmentId: a.id) }
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
        return Block(
            String(localized: .courseSectionUnits),
            note: file.units.count > shown.count ? String(localized: .courseUnitsNote(file.units.count, shown.count)) : nil
        ) {
            Card {
                if shown.isEmpty {
                    CardRow(last: true) { EmptyLine(String(localized: file.units.isEmpty ? .courseNoUnits : .courseNoCoveredUnits)) }
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                    let entry = reviews.first { $0.item.unitId == unit.id }
                    ReviewOpener(courseId: course.id, unitId: unit.id) {
                        CardRow(last: i == shown.count - 1) {
                            Text(unit.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            if let entry {
                                Chip(
                                    String(
                                        localized: entry.item.overdueDays > 0 ? .unitsDaysLate(entry.item.overdueDays) : .courseReviewToday),
                                    tone: entry.item.overdueDays > 0 ? .danger : .accent)
                            } else {
                                Text(.sessionsCount(unit.sessionIds.count)).font(Theme.Typeface.caption).foregroundStyle(
                                    Theme.Palette.textTertiary
                                ).fixedSize()
                            }
                        }
                    }
                    .contextMenu { UnitMenu(courseId: course.id, unitId: unit.id) }
                }
            }
            .opens { model.section = .units }
        }
    }

    func gradesBlock(_ file: CourseFile, score: GradeCalculator.CourseScore) -> some View {
        Block(
            String(localized: .courseSectionGrades),
            note: file.components.isEmpty ? nil : String(localized: .courseRemainingWeight(Int(score.remainingWeight.rounded())))
        ) {
            Card(padding: Theme.Space.l) {
                if file.components.isEmpty {
                    EmptyLine(String(localized: .courseNoComponents))
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                            Figure(String(localized: .courseSecured), score.secured.oneDecimal, font: Theme.Typeface.figureCompact)
                            Figure(
                                String(localized: .courseProjectedTitle), score.projected.map(\.oneDecimal) ?? "-", tint: accent.ink,
                                font: Theme.Typeface.figureCompact)
                        }
                        .sensitive()
                        WeightBar(components: file.components)
                    }
                }
            }
            .opens { model.section = .grades }
        }
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
