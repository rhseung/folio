import FolioActions
import FolioDomain
import SwiftUI

/// One semester: its period, courses, weekly timetable, exams and admin files (docs/SPEC.md "학기 화면").
struct SemesterView: View {
    @Environment(Workspace.self) private var workspace
    let semesterID: UUID
    let openCourse: (UUID) -> Void
    @Environment(\.searchTarget) private var searchTarget
    @State private var addingCourse = false

    var body: some View {
        if let semester = workspace.transcript.semesters.first(where: { $0.id == semesterID }) {
            let courses = workspace.courses(in: semester)
            let records = workspace.recordOnlyCourses(in: semester)
            let summary = GPACalculator.semester(semester, courses: workspace.allCourseRecords, catalog: workspace.catalog)
            Page {
                PageHeader(title: semester.title, subtitle: semester.term == .credited ? "인정받은 학점" : period(semester))

                StatStrip(items: [
                    .init(title: "과목", value: "\(courses.count + records.count)개"),
                    .init(title: "학점", value: (courses.map(\.file.course.credits) + records.map(\.credits)).reduce(0, +).formatted()),
                    .init(title: "성적 확정", value: "\(summary.totalCredits.formatted())학점", detail: "W 포함"),
                    .init(title: "학기 GPA", value: GPACalculator.label(summary.gpa), detail: summary.gpa == nil ? "진행 중" : "유효 \(summary.effectiveCredits.formatted())학점", sensitive: true),
                ])

                Block(title: "과목", note: "오른쪽에서 최종 성적을 고릅니다", trailing: { Button("과목 추가") { addingCourse = true }.buttonStyle(.ghost) }) {
                    Card {
                        if courses.isEmpty && records.isEmpty { CardRow(last: true) { EmptyLine("아직 과목이 없습니다") } }
                        ForEach(Array(courses.enumerated()), id: \.element.id) { i, course in
                            CardRow(last: i == courses.count - 1 && records.isEmpty) {
                                Button { openCourse(course.id) } label: {
                                    courseLabel(tile: IconTile(color: workspace.accent(course.id).color, symbol: course.file.course.icon ?? CourseMark.defaultIcon),
                                                title: course.title, detail: ([course.codeLine(workspace)] + course.factChips(workspace)).filter { !$0.isEmpty })
                                }
                                .buttonStyle(.pointing(.plain))
                                gradeMenu(course.file.course)
                            }
                            .contextMenu { courseMenu(course) }
                        }
                        ForEach(Array(records.enumerated()), id: \.element.id) { i, course in
                            CardRow(last: i == records.count - 1) {
                                courseLabel(tile: IconTile(color: Theme.Palette.textTertiary, symbol: "doc.text"), title: course.title,
                                            detail: ["\(course.credits.formatted())학점", course.gradingMode.label, "폴더 없이 성적만 기록"])
                                gradeMenu(course)
                            }
                        }
                    }
                }

                // A credited term is only a record of transferred credits: no dates, classes or exams.
                if semester.term != .credited {
                    Block("주간 시간표") {
                        Timetable(courses: courses, today: isCurrent(semester) ? workspace.today.date(in: workspace.calendar).map { workspace.calendar.isoWeekday(of: $0) } : nil, open: openCourse) { courseMenu($0) }
                    }

                    // Short lists of equal weight, side by side when there's room, as on Today.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.Space.xl, alignment: .top)], alignment: .leading, spacing: Theme.Space.xl) {
                        examsBlock(courses)
                        Block("기간") {
                            Card {
                                FormRow(label: "개강") { dateChip(semester, \.start) }
                                FormRow(label: "종강") { dateChip(semester, \.end) }
                                FormRow(label: "중간고사 주", detail: "시험 주에는 회차를 제안하지 않습니다") {
                                    examWeek(semester, \.midtermWeek, fallback: semester.defaultExamWeeks?.midterm)
                                }
                                FormRow(label: "기말고사 주", last: true) { examWeek(semester, \.finalWeek, fallback: semester.defaultExamWeeks?.final) }
                            }
                        }
                    }
                }

                let files = workspace.gist?.adminFiles(of: semester) ?? []
                if !files.isEmpty {
                    Block("학사 자료", note: StandardLayout.adminFolder) {
                        Card {
                            ForEach(Array(files.enumerated()), id: \.element) { i, url in
                                CardRow(last: i == files.count - 1) {
                                    Image(systemName: "doc").foregroundStyle(Theme.Palette.textSecondary)
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    #if os(macOS)
                                    Button("열기") { NSWorkspace.shared.open(url) }.buttonStyle(.ghost)
                                    #endif
                                }
                                #if os(macOS)
                                .contextMenu {
                                    Button("열기", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                                    Button("Finder에서 보기", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                                #endif
                            }
                        }
                    }
                }
            }
            .navigationTitle(semester.title)
            .sheet(isPresented: $addingCourse) { AddCourseSheet(semester: semester) { if let id = $0 { openCourse(id) } } }
        } else {
            ContentUnavailableView("학기를 찾지 못했습니다", systemImage: "calendar")
        }
    }

    /// `8월 31일 – 12월 18일 · 9주차`, the week only while the term runs.
    func period(_ s: Semester) -> String {
        let calendar = workspace.calendar
        guard let start = s.start?.date(in: calendar), let end = s.end?.date(in: calendar) else { return "기간 미정" }
        let format = Date.FormatStyle.dateTime.month().day()
        let week = isCurrent(s) ? " · 지금 \(SessionPlanner.week(of: .now, anchor: start, calendar: calendar))주차" : ""
        return "\(start.formatted(format)) – \(end.formatted(format))" + week
    }

    func isCurrent(_ s: Semester) -> Bool {
        guard let start = s.start, let end = s.end else { return false }
        return (start...end).contains(workspace.today)
    }

    /// The tile, the title and one muted line of facts, the same for a course with a folder and one only on record.
    func courseLabel(tile: IconTile, title: String, detail: [String]) -> some View {
        HStack(spacing: Theme.Space.m) {
            tile
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                Text(detail.joined(separator: " · ")).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.m)
        }
        .contentShape(.rect)
    }

    @ViewBuilder func courseMenu(_ course: LoadedCourse) -> some View {
        Button("열기", systemImage: "arrow.right.circle") { openCourse(course.id) }
        #if os(macOS)
        Button("Finder에서 보기", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
        #endif
    }

    /// RootView turns a search target into the course's selection, so this reaches its exams page from here.
    func showExams(_ course: UUID) {
        searchTarget.wrappedValue = SearchTarget(courseId: course, section: .exams)
    }

    func examsBlock(_ courses: [LoadedCourse]) -> some View {
        let exams = courses.flatMap { c in c.file.exams.compactMap { e in e.start.map { (c, e, $0) } } }.sorted { $0.2 < $1.2 }
        let now = Date.now
        return Block("시험 일정") {
            Card {
                if exams.isEmpty { CardRow(last: true) { EmptyLine("등록된 시험이 없습니다") } }
                ForEach(Array(exams.enumerated()), id: \.element.1.id) { i, item in
                    let (course, exam, start) = item
                    CardRow(last: i == exams.count - 1) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(start.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                            Text(start.formatted(.dateTime.weekday().hour().minute())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                        }
                        .frame(width: 84, alignment: .leading)
                        CourseDot(color: workspace.accent(course.id).color)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(exam.title.isEmpty ? exam.kind.label : exam.title).lineLimit(1)
                            Text(course.title).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                        if start > now {
                            DdayChip(days: workspace.days(to: start))
                        } else {
                            Text("끝남").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    // Past exams stay for reference but step back behind the coming ones.
                    .opacity(start > now ? 1 : 0.6)
                    .opens { showExams(course.id) }
                    .contextMenu { Button("시험 보기", systemImage: "calendar.badge.exclamationmark") { showExams(course.id) } }
                }
            }
        }
    }

    /// The recorded final grade, W included; 미정 until the semester's grades are out.
    @ViewBuilder func gradeMenu(_ course: Course) -> some View {
        let grades = workspace.catalog.grades(for: course.gradingMode)
        let selection = Binding(get: { course.finalGrade }, set: { g in workspace.run(CourseSet(course: course.id, [.finalGrade(g)])) })
        // A track reads as a scale; S/U has none, so it steps through its few symbols instead.
        if grades.contains(where: { $0.points != nil }) {
            GradeSteps(selection: selection, grades: grades.map { ($0.id, $0.symbol, $0.points != nil) })
                .sensitive(.control)
        } else {
            StepToggle(selection: selection, options: [.init(value: nil, label: "미정", tint: Theme.Palette.textTertiary)]
                       + grades.map { .init(value: $0.id, label: $0.symbol, tint: $0.countsInCredits ? Theme.Palette.success : Theme.Palette.textSecondary) },
                       ordered: false)
                .sensitive()
        }
    }

    /// A week of the term, labeled with its Monday when the start is known; unset, it shows the term's default.
    func examWeek(_ semester: Semester, _ key: WritableKeyPath<Semester, Int?>, fallback: Int?) -> some View {
        let calendar = workspace.calendar
        let anchor = semester.start?.date(in: calendar)
        let count = anchor.flatMap { a in semester.end?.date(in: calendar).map { SessionPlanner.week(of: $0, anchor: a, calendar: calendar) } } ?? 20
        let weeks = (1...max(count, fallback ?? 1)).map { w -> (Int?, String) in
            let monday = anchor.flatMap { calendar.date(byAdding: .day, value: (w - 1) * 7, to: calendar.startOfWeek(containing: $0)) }
            return (w, "\(w)주차" + (monday.map { " · \($0.formatted(.dateTime.month().day()))부터" } ?? ""))
        }
        return ChoiceMenu(selection: Binding(get: { semester[keyPath: key] ?? fallback }, set: { w in workspace.run(key == \Semester.midtermWeek ? SemesterSet(semester: semester.id, midtermWeek: .set(w)) : SemesterSet(semester: semester.id, finalWeek: .set(w))) }),
                          options: (fallback == nil ? [(nil, "없음")] : []) + weeks)
    }

    /// A date-only chip bound to the semester's start or end, saved as soon as it changes.
    func dateChip(_ semester: Semester, _ key: WritableKeyPath<Semester, LocalDate?>) -> some View {
        let calendar = workspace.calendar
        let binding = Binding<Date>(
            get: { semester[keyPath: key]?.date(in: calendar) ?? .now },
            set: { new in
                let day = LocalDate(new, in: calendar)
                workspace.run(key == \Semester.start ? SemesterSet(semester: semester.id, start: .set(day)) : SemesterSet(semester: semester.id, end: .set(day)))
            }
        )
        return Group {
            if semester[keyPath: key] == nil {
                Button("정하기") { binding.wrappedValue = .now }.buttonStyle(.ghost)
            } else {
                DateChip(date: binding, showsTime: false)
            }
        }
    }
}

/// The week as a time grid: a column per weekday (Saturday and Sunday only when used), each class placed at its hour
/// and as tall as it lasts, so free periods and back-to-back classes read at a glance.
struct Timetable<Menu: View>: View {
    @Environment(Workspace.self) private var workspace
    let courses: [LoadedCourse]
    /// The ISO weekday to mark, while the semester is running.
    var today: Int?
    let open: (UUID) -> Void
    @ViewBuilder let menu: (LoadedCourse) -> Menu

    static var hourHeight: CGFloat { 48 }
    static var gutter: CGFloat { 28 }

    var body: some View {
        let slots = courses.flatMap { c in c.file.course.schedule.map { (c, $0) } }
        let days = Array(1...max(5, slots.map(\.1.weekday).max() ?? 5))
        let first = (slots.map(\.1.startMinute).min() ?? 9 * 60) / 60
        let last = ((slots.map(\.1.endMinute).max() ?? 18 * 60) + 59) / 60
        let height = CGFloat(max(last - first, 1)) * Self.hourHeight
        Card(padding: Theme.Space.m) {
            if slots.isEmpty {
                EmptyLine("과목의 강의 화면에서 수업 시간을 넣으면 여기에 모입니다").padding(Theme.Space.xs)
            } else {
                VStack(spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.xs) {
                        Color.clear.frame(width: Self.gutter, height: 1)
                        ForEach(days, id: \.self) { day in
                            Text(ClassTime.weekdayNames[day - 1])
                                .font(Theme.Typeface.label)
                                .foregroundStyle(day == today ? Theme.Palette.text : Theme.Palette.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(first..<last, id: \.self) { hour in
                                Text("\(hour)").font(Theme.Typeface.label.weight(.regular)).monospacedDigit()
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .frame(height: Self.hourHeight, alignment: .top)
                            }
                        }
                        .frame(width: Self.gutter, alignment: .trailing)
                        ForEach(days, id: \.self) { day in
                            column(slots.filter { $0.1.weekday == day }, first: first, height: height)
                                .background(day == today ? Theme.Palette.fill.opacity(0.5) : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                        }
                    }
                    .background(alignment: .top) {
                        // Hour rules behind the columns, starting where the gutter's labels end.
                        VStack(spacing: 0) {
                            ForEach(first..<last, id: \.self) { _ in
                                Theme.Palette.lineSoft.frame(height: 1).frame(height: Self.hourHeight, alignment: .top)
                            }
                        }
                        .padding(.leading, Self.gutter + Theme.Space.xs)
                    }
                }
            }
        }
    }

    // shortcut: two classes at the same time on one day draw over each other; split the column if that ever happens.
    func column(_ slots: [(LoadedCourse, ClassTime)], first: Int, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(Array(slots.enumerated()), id: \.offset) { _, item in
                let (course, slot) = item
                let accent = workspace.accent(course.id)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.title).font(Theme.Typeface.caption.weight(.semibold)).lineLimit(2)
                    Text(TimeMenu.label(slot.startMinute) + (slot.room.isEmpty ? "" : " · \(slot.room)"))
                        .font(Theme.Typeface.label.weight(.regular)).monospacedDigit().lineLimit(1)
                }
                .foregroundStyle(accent.ink)
                .padding(.horizontal, Theme.Space.tight)
                .padding(.vertical, Theme.Space.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: max(CGFloat(slot.endMinute - slot.startMinute) / 60 * Self.hourHeight - 2, 20))
                .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.control - 2))
                .overlay(alignment: .leading) { accent.color.frame(width: 4).clipShape(.rect(cornerRadius: Theme.Radius.mark)) }
                .clipShape(.rect(cornerRadius: Theme.Radius.control - 2))
                .opens { open(course.id) }
                .contextMenu { menu(course) }
                .offset(y: CGFloat(slot.startMinute - first * 60) / 60 * Self.hourHeight + 1)
                .help("\(course.title) · \(TimeMenu.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " · \(slot.room)"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

/// Year, term and period for a new semester; creates its folder.
struct AddSemesterSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let created: (UUID?) -> Void
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var term: Term = .fall
    @State private var start = Date.now
    @State private var end = Calendar.current.date(byAdding: .month, value: 4, to: .now) ?? .now

    var body: some View {
        let exists = workspace.transcript.semesters.contains { $0.year == year && $0.term == term }
        SheetForm(title: "학기 추가", confirm: "추가", disabled: exists, note: exists ? "이미 있는 학기입니다" : SemesterFolder(year: year, term: term).map { "폴더 \($0.name)을 만듭니다" }) {
            FormRow(label: "연도") {
                ScrubField(value: Binding(get: { Double(year) }, set: { year = Int($0.rounded()) }), range: 2000...2100, step: 1, width: 88)
            }
            FormRow(label: "학기") { ChoiceMenu(selection: $term, options: [Term.spring, .summer, .fall, .winter].map { ($0, $0.label) }) }
            FormRow(label: "개강") { DateChip(date: $start, showsTime: false) }
            FormRow(label: "종강", last: true) { DateChip(date: $end, showsTime: false) }
        } onConfirm: {
            let c = workspace.calendar
            created(workspace.addSemester(year: year, term: term, start: LocalDate(start, in: c), end: LocalDate(end, in: c)))
            dismiss()
        }
        .onAppear {
            // Opens on the term after the newest one, which is the one usually being added.
            guard let newest = workspace.semesters.first else { return }
            let order: [Term] = [.spring, .summer, .fall, .winter]
            let i = order.firstIndex(of: newest.term) ?? 0
            (year, term) = i + 1 < order.count ? (newest.year, order[i + 1]) : (newest.year + 1, order[0])
        }
    }
}

/// Name, code, number, credits and grading for a new course; creates `<code><number> <title>`.
struct AddCourseSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let semester: Semester
    let created: (UUID?) -> Void
    @State private var title = ""
    @State private var codeId: UUID?
    @State private var number = ""
    @State private var credits: Double? = 3
    @State private var mode: GradingMode = .relative

    var body: some View {
        let codes = workspace.catalog.codes.sorted { $0.prefix < $1.prefix }
        let prefix = codes.first { $0.id == codeId }?.prefix ?? ""
        let folder = StandardLayout.courseFolderName(prefix: prefix, number: number, title: title)
        SheetForm(title: "\(semester.title) 과목 추가", confirm: "추가", disabled: folder == nil || codeId == nil || (credits ?? -1) < 0,
                  note: folder.map { "폴더 \($0)을 만듭니다" } ?? "강의 코드, 번호(예: 4207-01), 이름을 넣으면 폴더 이름이 정해집니다") {
            FormRow(label: "이름") { InlineField("예: 그래프 이론", text: $title) }
            // Prefix and number side by side, as in 과목 편집 and as the course reads: GS2004-02.
            FormRow(label: "강의 코드") {
                SearchSelect(selection: $codeId, options: codes.map { PickOption(id: Optional($0.id), title: $0.prefix, detail: [$0.department, $0.program].filter { !$0.isEmpty }.joined(separator: " · ")) })
                TextField("4207-01", text: $number).pill(width: 100)
            }
            FormRow(label: "학점") { CreditsField(credits: $credits) }
            FormRow(label: "평가 방식", last: true) {
                ChoiceMenu(selection: $mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
            }
        } onConfirm: {
            guard let codeId, let credits else { return }
            created(workspace.run(CourseAdd(semester: semester.id, title: title, code: codeId, number: number, credits: credits, mode: mode))?.made)
            dismiss()
        }
    }
}

extension Term {
    var label: String {
        switch self {
        case .spring: "봄학기"
        case .summer: "여름학기"
        case .fall: "가을학기"
        case .winter: "겨울학기"
        case .credited: "인정학기"
        }
    }
}
