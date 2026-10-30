import FolioActions
import FolioDomain
import SwiftUI

struct SemesterView: View {
    @State private var model: SemesterModel
    let openCourse: (UUID) -> Void
    @Environment(\.searchTarget) private var searchTarget
    @State private var addingCourse = false

    init(workspace: Workspace, semesterID: UUID, openCourse: @escaping (UUID) -> Void) {
        _model = State(initialValue: SemesterModel(workspace: workspace, semesterID: semesterID))
        self.openCourse = openCourse
    }

    var body: some View {
        if let semester = model.semester {
            let courses = model.courses(in: semester)
            let records = model.records(in: semester)
            Page {
                PageHeader(title: semester.title, subtitle: model.subtitle(semester))

                StatStrip(items: model.stats(semester))

                Block(title: String(localized: .semesterCourses), note: String(localized: .semesterCoursesNote), trailing: { Button(.semesterCoursesAdd) { addingCourse = true }.buttonStyle(.ghost) }) {
                    Card {
                        if courses.isEmpty && records.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .semesterCoursesEmpty)) } }
                        ForEach(Array(courses.enumerated()), id: \.element.id) { i, course in
                            CardRow(last: i == courses.count - 1 && records.isEmpty) {
                                Button { openCourse(course.id) } label: {
                                    courseLabel(mark: CourseMark(icon: course.file.course.icon, color: model.workspace.accent(course.id).color, font: Theme.Glyph.lineTitle, duotone: true),
                                                title: course.title, detail: model.detail(course))
                                }
                                .buttonStyle(.pointing(.plain))
                                gradeMenu(course.file.course)
                            }
                            .contextMenu { courseMenu(course) }
                        }
                        ForEach(Array(records.enumerated()), id: \.element.id) { i, course in
                            CardRow(last: i == records.count - 1) {
                                courseLabel(mark: CourseMark(icon: "doc.text", color: Theme.Palette.textTertiary, font: Theme.Glyph.lineTitle, duotone: true), title: course.title, detail: model.detail(course))
                                gradeMenu(course)
                            }
                        }
                    }
                }

                // A credited term is only a record of transferred credits: no dates, classes or exams.
                if semester.term != .credited {
                    Block(String(localized: .semesterTimetable)) {
                        Timetable(model: model, courses: courses, today: model.markedWeekday(semester), open: openCourse) { courseMenu($0) }
                    }

                    // Short lists of equal weight, side by side when there's room, as on Today.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.Space.xl, alignment: .top)], alignment: .leading, spacing: Theme.Space.xl) {
                        examsBlock(courses)
                        Block(String(localized: .semesterPeriod)) {
                            Card {
                                FormRow(label: String(localized: .semesterStart)) { dateChip(semester, \.start) }
                                FormRow(label: String(localized: .semesterEnd)) { dateChip(semester, \.end) }
                                FormRow(label: String(localized: .semesterMidtermWeek), detail: String(localized: .semesterMidtermWeekDetail)) {
                                    examWeek(semester, \.midtermWeek, fallback: semester.defaultExamWeeks?.midterm)
                                }
                                FormRow(label: String(localized: .semesterFinalWeek), last: true) { examWeek(semester, \.finalWeek, fallback: semester.defaultExamWeeks?.final) }
                            }
                        }
                    }
                }

                let files = model.adminFiles(semester)
                if !files.isEmpty {
                    Block(String(localized: .semesterAdmin), note: StandardLayout.adminFolder) {
                        Card {
                            ForEach(Array(files.enumerated()), id: \.element) { i, url in
                                CardRow(last: i == files.count - 1) {
                                    Image(systemName: "doc").foregroundStyle(Theme.Palette.textSecondary)
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    #if os(macOS)
                                    Button(.commonOpen) { NSWorkspace.shared.open(url) }.buttonStyle(.ghost)
                                    #endif
                                }
                                #if os(macOS)
                                .contextMenu {
                                    Button(.commonOpen, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                                    Button(.commonShowInFinder, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                                #endif
                            }
                        }
                    }
                }
            }
            .navigationTitle(semester.title)
            .sheet(isPresented: $addingCourse) { AddCourseSheet(workspace: model.workspace, semester: semester) { if let id = $0 { openCourse(id) } } }
        } else {
            ContentUnavailableView(String(localized: .semesterNotFound), systemImage: "calendar")
        }
    }

    func courseLabel(mark: CourseMark, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            mark
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.m)
        }
        .contentShape(.rect)
    }

    @ViewBuilder func courseMenu(_ course: LoadedCourse) -> some View {
        Button(.commonOpen, systemImage: "arrow.right.circle") { openCourse(course.id) }
        #if os(macOS)
        Button(.commonShowInFinder, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
        #endif
    }

    /// RootView turns a search target into the course's selection, so this reaches its exams page from here.
    func showExams(_ course: UUID) {
        searchTarget.wrappedValue = SearchTarget(courseId: course, section: .exams)
    }

    func examsBlock(_ courses: [LoadedCourse]) -> some View {
        let exams = model.exams(of: courses)
        let now = model.workspace.now
        return Block(String(localized: .semesterExams)) {
            Card {
                if exams.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .semesterExamsEmpty)) } }
                ForEach(Array(exams.enumerated()), id: \.element.exam.id) { i, item in
                    let start = item.start
                    CardRow(last: i == exams.count - 1) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(start.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                            Text(start.formatted(.dateTime.weekday().hour().minute())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                        }
                        .frame(width: 84, alignment: .leading)
                        CourseMark(model.workspace, item.course.id)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(model.examTitle(item.exam)).lineLimit(1)
                            Text(item.course.title).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                        if start > now {
                            DdayChip(days: model.workspace.days(to: start))
                        } else {
                            Text(.commonEnded).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    // Past exams stay for reference but step back behind the coming ones.
                    .opacity(start > now ? 1 : 0.6)
                    .opens { showExams(item.course.id) }
                    .contextMenu { Button(.commonShowExams, systemImage: "calendar.badge.exclamationmark") { showExams(item.course.id) } }
                }
            }
        }
    }

    @ViewBuilder func gradeMenu(_ course: Course) -> some View {
        let grades = model.grades(for: course)
        let selection = Binding(get: { course.finalGrade }, set: { model.setFinalGrade($0, of: course) })
        // A track reads as a scale; S/U has none, so it steps through its few symbols instead.
        if grades.contains(where: { $0.points != nil }) {
            GradeSteps(selection: selection, grades: grades.map { ($0.id, $0.symbol, $0.points != nil) })
                .sensitive(.control)
        } else {
            StepToggle(selection: selection, options: [.init(value: nil, label: String(localized: .semesterGradeNone), tint: Theme.Palette.textTertiary)]
                       + grades.map { .init(value: $0.id, label: $0.symbol, tint: $0.countsInCredits ? Theme.Palette.success : Theme.Palette.textSecondary) },
                       ordered: false)
                .sensitive()
        }
    }

    func examWeek(_ semester: Semester, _ key: WritableKeyPath<Semester, Int?>, fallback: Int?) -> some View {
        ChoiceMenu(selection: Binding(get: { semester[keyPath: key] ?? fallback }, set: { model.setWeek(semester, key, to: $0) }),
                   options: model.weekOptions(semester, fallback: fallback))
    }

    func dateChip(_ semester: Semester, _ key: WritableKeyPath<Semester, LocalDate?>) -> some View {
        let binding = Binding<Date>(get: { model.date(semester, key) }, set: { model.setDate(semester, key, to: $0) })
        return Group {
            if semester[keyPath: key] == nil {
                Button(.semesterDateSet) { binding.wrappedValue = .now }.buttonStyle(.ghost)
            } else {
                DateChip(date: binding, showsTime: false)
            }
        }
    }
}

/// The week as a time grid: a column per weekday (Saturday and Sunday only when used), each class placed at its hour
/// and as tall as it lasts, so free periods and back-to-back classes read at a glance.
struct Timetable<Menu: View>: View {
    let model: SemesterModel
    let courses: [LoadedCourse]
    /// The ISO weekday to mark, while the semester is running.
    var today: Int?
    let open: (UUID) -> Void
    @ViewBuilder let menu: (LoadedCourse) -> Menu

    static var hourHeight: CGFloat { 48 }
    static var gutter: CGFloat { 28 }

    var body: some View {
        let layout = TimetableLayout(courses: courses)
        let (days, first, last) = (layout.days, layout.first, layout.last)
        let height = CGFloat(max(last - first, 1)) * Self.hourHeight
        Card(padding: Theme.Space.m) {
            if layout.slots.isEmpty {
                EmptyLine(String(localized: .semesterTimetableEmpty)).padding(Theme.Space.xs)
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
                            column(layout.slots(on: day), first: first, height: height)
                                .background(day == today ? Theme.Palette.fill.opacity(0.5) : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                        }
                    }
                    .background(alignment: .top) {
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
    func column(_ slots: [(course: LoadedCourse, time: ClassTime)], first: Int, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(Array(slots.enumerated()), id: \.offset) { _, item in
                let (course, slot) = item
                let accent = model.workspace.accent(course.id)
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

struct AddSemesterSheet: View {
    @State private var model: AddSemesterModel
    @Environment(\.dismiss) private var dismiss
    let created: (UUID?) -> Void

    init(workspace: Workspace, created: @escaping (UUID?) -> Void) {
        _model = State(initialValue: AddSemesterModel(workspace: workspace))
        self.created = created
    }

    var body: some View {
        SheetForm(title: String(localized: .semesterAddTitle), confirm: String(localized: .commonAdd), disabled: model.exists, note: model.note) {
            FormRow(label: String(localized: .semesterAddYear)) {
                ScrubField(value: Binding(get: { Double(model.year) }, set: { model.year = Int($0.rounded()) }), range: 2000...2100, step: 1, width: 88)
            }
            FormRow(label: String(localized: .semesterAddTerm)) { ChoiceMenu(selection: $model.term, options: AddSemesterModel.terms.map { ($0, $0.label) }) }
            FormRow(label: String(localized: .semesterStart)) { DateChip(date: $model.start, showsTime: false) }
            FormRow(label: String(localized: .semesterEnd), last: true) { DateChip(date: $model.end, showsTime: false) }
        } onConfirm: {
            created(model.add())
            dismiss()
        }
    }
}

struct AddCourseSheet: View {
    @State private var model: AddCourseModel
    @Environment(\.dismiss) private var dismiss
    let created: (UUID?) -> Void

    init(workspace: Workspace, semester: Semester, created: @escaping (UUID?) -> Void) {
        _model = State(initialValue: AddCourseModel(workspace: workspace, semester: semester))
        self.created = created
    }

    var body: some View {
        SheetForm(title: String(localized: .semesterAddCourseTitle(model.semester.title)), confirm: String(localized: .commonAdd), disabled: model.disabled, note: model.note) {
            FormRow(label: String(localized: .semesterAddCourseName)) { InlineField(String(localized: .semesterAddCourseNameExample), text: $model.title) }
            // Prefix and number side by side, as in 과목 편집 and as the course reads: GS2004-02.
            FormRow(label: String(localized: .semesterAddCourseCode)) {
                SearchSelect(selection: $model.codeId, options: model.codes.map { PickOption(id: Optional($0.id), title: $0.prefix, detail: [$0.department, $0.program].filter { !$0.isEmpty }.joined(separator: " · ")) })
                TextField("4207-01", text: $model.number).pill(width: 100)
            }
            FormRow(label: String(localized: .semesterCreditsLabel)) { CreditsField(credits: $model.credits) }
            FormRow(label: String(localized: .semesterAddCourseMode), last: true) {
                ChoiceMenu(selection: $model.mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
            }
        } onConfirm: {
            guard !model.disabled else { return }
            created(model.add())
            dismiss()
        }
    }
}
