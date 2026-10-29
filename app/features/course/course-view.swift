import FolioDomain
import SwiftUI

enum CourseSection: String, CaseIterable, Identifiable {
    case overview = "개요", sessions = "회차", units = "단원", notes = "노트", materials = "자료"
    case quizSolve = "풀기", quizCards = "카드", quizStats = "오답과 통계", quizProblems = "문제 묶음"
    case assignments = "과제", exams = "시험", grades = "성적"
    var id: Self { self }

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

enum CourseTab: String, CaseIterable, Identifiable {
    case overview = "개요", classes = "수업", notes = "노트", materials = "자료", quiz = "퀴즈", assessment = "평가"
    var id: Self { self }

    var pages: [CourseSection] { CourseSection.allCases.filter { $0.tab == self } }

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
    @Environment(Workspace.self) private var workspace
    let courseID: UUID
    @State private var section: CourseSection = .overview
    @State private var openNote: UUID?
    @State private var showClaude = false
    /// An answer the Claude panel puts at the end of the open note; the editor takes it and clears it.
    @State private var noteInsert: String?
    @State private var claudeWidth = Theme.Size.claudePanel
    @State private var pageReset = 0
    @State private var claudeDragBase: CGFloat?
    @Environment(\.searchTarget) private var searchTarget

    func claude(_ course: LoadedCourse) -> some View {
        ClaudePanel(course: course, openNote: section == .notes ? openNote : nil, insertIntoNote: { noteInsert = $0 }) {
            openNote = $0
            section = .notes
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
                    .foregroundStyle(showClaude ? Theme.Palette.textSecondary : workspace.accent(courseID).color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Theme.Size.fab, height: Theme.Size.fab)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.pointing(.plain))
            .help(showClaude ? "Claude 닫기" : "Claude에게 묻기")
            .accessibilityLabel(showClaude ? "Claude 닫기" : "Claude")
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
        if let course = workspace.course(courseID) {
            HStack(spacing: 0) {
                CourseColumn(course: course, section: $section, selectedNote: $openNote)
                    .frame(width: Theme.Size.courseColumn)
                    // Back to the section's first screen from a file or unit opened in it.
                    .crumb(section.rawValue, level: 1, symbol: section.tab.symbol) { pageReset += 1 }
                ColumnDivider()
                Group {
                    switch section {
                    case .overview: CourseOverview(course: course, section: $section) { openNote = $0; section = .notes }
                    case .sessions: SessionsView(course: course) { openNote = $0; section = .notes }
                    case .units: UnitsView(course: course)
                    case .notes: NotesView(course: course, selection: openNote, insert: $noteInsert) { openNote = $0 }
                    // One branch for every quiz page, so the quiz model and a pending solve request survive switching pages.
                    case .quizSolve, .quizCards, .quizStats, .quizProblems: QuizView(workspace: workspace, course: course, section: $section)
                    case .materials: MaterialsView(course: course)
                    case .assignments: AssignmentsView(course: course)
                    case .grades: CourseGradesView(course: course)
                    case .exams: ExamsView(course: course) { openNote = $0; section = .notes }
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
            .environment(\.accent, workspace.accent(courseID))
            .tint(workspace.accent(courseID).ink)
            .navigationTitle(course.title)
            .navigationSubtitle(section.rawValue)
            .studyTime(course: courseID)
            .onChange(of: searchTarget.wrappedValue, initial: true) { _, target in
                guard let target, target.courseId == courseID else { return }
                section = target.section
                if let note = target.noteId { openNote = note }
                // A material target is left for MaterialsView, which opens the file and then clears it.
                if target.materialId == nil { searchTarget.wrappedValue = nil }
            }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.section, initial: true) { _, new in if let new { section = new } }
            .onChange(of: SnapshotDriver.shared.claudePanel, initial: true) { _, new in showClaude = new }
            #endif
        } else {
            ContentUnavailableView("과목을 찾지 못했습니다", systemImage: "questionmark.folder")
        }
    }
}

struct CourseColumn: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    @Binding var section: CourseSection
    @Binding var selectedNote: UUID?

    func openNote(_ id: UUID) {
        selectedNote = id
        section = .notes
    }

    var body: some View {
        let file = course.file
        let score = GradeCalculator.score(components: file.components, entries: file.scores)
        let unclassified = file.materials.filter { $0.status == .unclassified }.count
        let recent = file.sessions.filter { $0.date <= .now && !$0.isCancelled }.sorted { $0.date > $1.date }.prefix(4)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
                // Code and name only; credits, grading and professors are on the overview page.
                // Laid out like a ColumnRow, the dot in the icon column, so the title and the rows below share their edges.
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.codeLine(workspace)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.leading, ColumnRow<EmptyView>.titleInset - Theme.Inset.listRow.leading)
                    HStack(spacing: ColumnRow<EmptyView>.gap) {
                        CourseMark(icon: course.file.course.icon, color: accent.color, font: Theme.Glyph.lineTitle)
                        Text(course.title).font(Theme.Typeface.columnTitle).lineLimit(2)
                    }
                }
                .padding(.horizontal, Theme.Inset.listRow.leading)

                VStack(spacing: Theme.Space.xxs) {
                    ForEach(CourseTab.allCases) { item in
                        let chosen = section.tab == item
                        Button { if !chosen { section = item.pages[0] } } label: {
                            ColumnRow(title: item.rawValue, symbol: item.symbol, chosen: chosen, tint: accent.color, fill: accent.tint) {
                                trailing(item, file: file, score: score, unclassified: unclassified)
                            }
                        }
                        .buttonStyle(.pointing(.plain))
                        if chosen, item.pages.count > 1 {
                            ForEach(item.pages) { page in
                                Button { section = page } label: {
                                    Text(page.rawValue)
                                        .foregroundStyle(section == page ? accent.ink : Theme.Palette.textSecondary)
                                        .fontWeight(section == page ? .semibold : .regular)
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

                if section == .notes {
                    NoteList(course: course, selection: $selectedNote)
                } else if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Caption("최근 강의").padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.tight)
                        ForEach(Array(recent)) { session in
                            Button {
                                if let id = session.roughNoteId ?? session.reviewNoteId { openNote(id) } else { section = .sessions }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(session.topic.isEmpty ? course.file.name(of: session) : "\(course.file.name(of: session)) · \(session.topic)").lineLimit(1)
                                    Text(session.date.formatted(.dateTime.month().day().weekday()) + " · " + noteState(session))
                                        .font(Theme.Typeface.label.weight(.regular))
                                        .foregroundStyle(course.file.needsReviewNote(session, at: .now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                                }
                                .padding(Theme.Inset.listRow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu { SessionMenu(courseId: course.id, sessionId: session.id, openNote: openNote) { section = .sessions } }
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

    @ViewBuilder func trailing(_ item: CourseTab, file: CourseFile, score: GradeCalculator.CourseScore, unclassified: Int) -> some View {
        switch item {
        case .classes where !file.sessions.isEmpty: count("\(file.sessions.count)회")
        case .materials where unclassified > 0: Chip("미분류 \(unclassified)", tone: .warning)
        case .assessment: if workspace.gradesUnlocked, let p = score.projected { count("예상 \(p.oneDecimal)") }
        default: EmptyView()
        }
    }

    func count(_ text: String) -> some View {
        Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
    }

    func noteState(_ session: Session) -> String {
        if session.reviewNoteId != nil { return session.reviewNoteUnfinished ? "복습 노트 작성 중" : "복습 노트" }
        if session.roughNoteId != nil { return "러프 노트" }
        return course.file.needsReviewNote(session, at: .now) ? "복습 노트 없음" : "복습 필요 없음"
    }
}

struct CourseOverview: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    @Binding var section: CourseSection
    let openNote: (UUID) -> Void
    @State private var editing = false
    @State private var wide = true

    var body: some View {
        let file = course.file
        let now = Date.now
        let score = GradeCalculator.score(components: file.components, entries: file.scores)
        let reviews = workspace.reviewQueue(now: now).filter { $0.courseId == course.id }
        let suggested = workspace.suggestedSession(for: course, now: now)
        let unclassified = file.materials.filter { $0.status == .unclassified }
        // Two columns that each run as long as their own blocks; a grid row made the short week card as tall as the units.
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.xl)) : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xl))

        Page {
            PageHeader(title: course.title, subtitle: [workspace.semester(of: file.course)?.title, scheduleLine(file.course.schedule)].compactMap { $0 }.joined(separator: " · ")) {
                let code = course.codeLine(workspace)
                if !code.isEmpty { Chip(code, tone: .accent) }
                Chip("\(file.course.credits.formatted())학점")
                Chip(file.course.gradingMode.label)
                Spacer()
                Button("과목 편집", systemImage: "slider.horizontal.3") { editing = true }.buttonStyle(.ghost)
            }
            .sheet(isPresented: $editing) { EditCourseSheet(course: course) }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.editCourse, initial: true) { _, on in editing = on }
            #endif

            StatStrip(items: stats(file: file, reviews: reviews, suggested: suggested, now: now))

            if !unclassified.isEmpty {
                NoticeCard(title: "자료 \(unclassified.count)건이 분류를 기다립니다", detail: "승인하기 전에는 옮기지 않습니다", systemImage: "tray.fill") {
                    Button("검토하기") { section = .materials }.buttonStyle(.ghost)
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
        let calendar = workspace.calendar
        // Monday-based like the app's weeks; the calendar's own week can start on Sunday.
        let start = calendar.startOfWeek(containing: now)
        let week = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        let sessions = file.sessions.filter { week.contains($0.date) }.sorted { $0.date < $1.date }
        let next = suggested.flatMap { week.contains($0.suggestion.date) ? $0 : nil }
        return Block("이번 주 강의") {
            if !sessions.isEmpty || next == nil {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine("이번 주에는 수업이 없습니다") } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) {
                            VStack(spacing: 0) {
                                Text(s.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
                                // The bare number: Korean's day format adds 일, which overflowed the 34pt column.
                                Text(verbatim: "\(calendar.component(.day, from: s.date))").font(Theme.Typeface.figureMedium).foregroundStyle(s.date > now ? accent.ink : Theme.Palette.text)
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(s.topic.isEmpty ? file.name(of: s) : "\(file.name(of: s)) · \(s.topic)").font(Theme.Typeface.bodyStrong).lineLimit(1)
                                    .strikethrough(s.isCancelled)
                                Text(s.isCancelled ? "휴강" : s.date > now ? "예정" : s.reviewNoteId != nil ? (s.reviewNoteUnfinished ? "복습 노트 작성 중" : "복습 노트") : file.needsReviewNote(s, at: now) ? "복습 노트 없음" : "복습 필요 없음")
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(file.needsReviewNote(s, at: now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu { SessionMenu(courseId: course.id, sessionId: s.id, openNote: openNote) { section = .sessions } }
                    }
                }
                .opens { section = .sessions }
            }
            // The class the timetable says comes next, before it is made: starting its note makes it, as on Today.
            if let next { SuggestedSessionRow(item: next, openNote: openNote) }
        }
    }

    func assignmentsBlock(_ file: CourseFile, now: Date) -> some View {
        let open = file.assignments.filter(\.status.isOpen).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let shown = Array(open.prefix(5))
        let done = file.assignments.count - open.count
        return Block("과제", note: file.assignments.isEmpty ? nil : "\(file.assignments.count)개 중 \(done)개 끝남") {
            Card {
                if shown.isEmpty { CardRow(last: true) { EmptyLine(file.assignments.isEmpty ? "과제가 없습니다" : "남은 과제가 없습니다") } }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                    CardRow(last: i == shown.count - 1 && open.count == shown.count) {
                        Image(systemName: a.status.symbol).foregroundStyle(a.status.tint)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(a.due?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? "마감 없음")
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                        }
                        Spacer(minLength: Theme.Space.s)
                        if let due = a.due {
                            if due < now {
                                Chip("마감 지남", tone: .danger)
                            } else {
                                DdayChip(days: workspace.days(to: due))
                            }
                        }
                    }
                    .contextMenu { Button("과제 보기", systemImage: "checklist") { section = .assignments } }
                }
                if open.count > shown.count {
                    CardRow(last: true) { EmptyLine("외 \(open.count - shown.count)개") }
                }
            }
            .opens { section = .assignments }
        }
    }

    /// A glance, not the list: the units due first, then the ones taught most recently.
    func unitsBlock(_ file: CourseFile, reviews: [Workspace.ReviewEntry]) -> some View {
        let due = reviews.compactMap { r in file.units.first { $0.id == r.item.unitId } }
        let covered = UnitTree.outline(file.units).map(\.unit).filter { u in !u.sessionIds.isEmpty && !due.contains { $0.id == u.id } }
        let shown = Array((due + covered.suffix(8).reversed()).prefix(8))
        return Block("단원", note: file.units.count > shown.count ? "\(file.units.count)개 중 \(shown.count)개" : nil) {
            Card {
                if shown.isEmpty { CardRow(last: true) { EmptyLine(file.units.isEmpty ? "단원이 없습니다" : "아직 다룬 단원이 없습니다") } }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                    let entry = reviews.first { $0.item.unitId == unit.id }
                    ReviewOpener(courseId: course.id, unitId: unit.id) {
                        CardRow(last: i == shown.count - 1) {
                            Text(unit.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            if let entry {
                                Chip(entry.item.overdueDays > 0 ? "\(entry.item.overdueDays)일 밀림" : "오늘 복습", tone: entry.item.overdueDays > 0 ? .danger : .accent)
                            } else {
                                Text("회차 \(unit.sessionIds.count)개").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("단원 보기", systemImage: "list.bullet") { section = .units }
                        if entry != nil {
                            Button("오늘 복습 건너뛰기", systemImage: "forward") { workspace.skipReviews([(course.id, unit.id)]) }
                        }
                    }
                }
            }
            .opens { section = .units }
        }
    }

    func gradesBlock(_ file: CourseFile, score: GradeCalculator.CourseScore) -> some View {
        Block("성적", note: file.components.isEmpty ? nil : "남은 비중 \(Int(score.remainingWeight.rounded()))%") {
            Card(padding: Theme.Space.l) {
                if file.components.isEmpty {
                    EmptyLine("평가 항목이 없습니다")
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                            Figure("확보", score.secured.oneDecimal, font: Theme.Typeface.figureCompact)
                            Figure("예상", score.projected.map(\.oneDecimal) ?? "-", tint: accent.ink, font: Theme.Typeface.figureCompact)
                        }
                        .sensitive()
                        // Names live in the segment tooltips and on the grades page; listed here they swamp the card.
                        WeightBar(components: file.components)
                    }
                }
            }
            .opens { section = .grades }
        }
    }

    /// `월·수 13:00–14:15 자연과학동 203`: days sharing a time and room are written once.
    func scheduleLine(_ schedule: [ClassTime]) -> String? {
        var groups: [(key: String, days: [String])] = []
        for slot in schedule.sorted(by: { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }) {
            let key = "\(TimeMenu.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " \(slot.room)")
            let day = ClassTime.weekdayNames[slot.weekday - 1]
            if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].days.append(day) } else { groups.append((key, [day])) }
        }
        return groups.isEmpty ? nil : groups.map { $0.days.joined(separator: "·") + " " + $0.key }.joined(separator: ", ")
    }

    func stats(file: CourseFile, reviews: [Workspace.ReviewEntry], suggested: Workspace.SuggestedSession?, now: Date) -> [StatStrip.Item] {
        // A class the timetable promises counts before it is made; without it a course that makes sessions as it goes
        // never showed a next class.
        let made: (date: Date, name: String)? = file.sessions.filter { $0.date > now && !$0.isCancelled }.min { $0.date < $1.date }
            .map { (date: $0.date, name: file.name(of: $0)) }
        let planned: (date: Date, name: String)? = suggested.flatMap { $0.suggestion.date > now ? (date: $0.suggestion.date, name: $0.name) : nil }
        let nextClass = [made, planned].compactMap { $0 }.min { $0.date < $1.date }
        let nextExam = file.exams.compactMap { e in e.start.map { (e, $0) } }.filter { $0.1 > now }.min { $0.1 < $1.1 }
        let nextDue = file.assignments.compactMap { a in a.due.map { (a, $0) } }
            .filter { $0.1 > now && $0.0.status.isOpen }.min { $0.1 < $1.1 }
        let maxOverdue = reviews.map(\.item.overdueDays).max() ?? 0

        var items: [StatStrip.Item] = []
        if let next = nextClass {
            // The weekday rides in the detail: with it the date was cut off in a narrow window.
            items.append(.init(title: "다음 수업", value: next.date.formatted(.dateTime.month().day()),
                               detail: "\(next.date.formatted(.dateTime.weekday())) \(next.date.formatted(date: .omitted, time: .shortened)) · \(next.name)"))
        } else {
            items.append(.init(title: "다음 수업", value: "-"))
        }
        if let (exam, start) = nextExam {
            let d = workspace.days(to: start)
            items.append(.init(title: "다음 시험", value: "\(exam.title.isEmpty ? exam.kind.label : exam.title) \(d == 0 ? "D-day" : "D-\(d)")",
                               detail: start.formatted(.dateTime.month().day().weekday()), tone: d <= 7 ? .danger : .plain))
        } else {
            items.append(.init(title: "다음 시험", value: "-"))
        }
        items.append(.init(title: "오늘 복습", value: "\(reviews.count)단원", detail: maxOverdue > 0 ? "최대 \(maxOverdue)일 밀림" : nil,
                           tone: maxOverdue > 0 ? .warning : .plain))
        items.append(.init(title: "가까운 마감", value: nextDue?.0.title ?? "-", detail: nextDue?.1.formatted(.dateTime.month().day().weekday().hour().minute())))
        // Each figure opens the page it sums up, in the order appended above.
        for (i, target) in [CourseSection.sessions, .exams, .units, .assignments].enumerated() { items[i].action = { section = target } }
        return items
    }
}

struct SessionMenu: View {
    @Environment(Workspace.self) private var workspace
    let courseId: UUID
    let sessionId: UUID
    let openNote: (UUID) -> Void
    let showSessions: () -> Void

    var body: some View {
        Button("러프 노트 열기", systemImage: "pencil.line") { if let id = workspace.note(.rough, of: sessionId, in: courseId) { openNote(id) } }
        Button("복습 노트 열기", systemImage: "square.and.pencil") { if let id = workspace.note(.review, of: sessionId, in: courseId) { openNote(id) } }
        if let session = workspace.course(courseId)?.file.sessions.first(where: { $0.id == sessionId }), session.reviewNoteId != nil {
            if session.reviewNoteUnfinished {
                Button("복습 노트 작성 완료", systemImage: "checkmark.circle") { workspace.setReviewNoteUnfinished(false, of: sessionId, in: courseId) }
            } else {
                Button("복습 노트 작성 중으로", systemImage: "arrow.uturn.backward") { workspace.setReviewNoteUnfinished(true, of: sessionId, in: courseId) }
            }
        }
        Button("회차 보기", systemImage: "calendar", action: showSessions)
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
        return ["\(c.credits.formatted())학점", c.gradingMode.label] + professors
    }
}

extension GradingMode {
    var label: String {
        switch self {
        case .relative: "상대평가"
        case .absolute: "절대평가"
        case .passFail: "S/U"
        }
    }
}
