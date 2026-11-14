import FolioActions
import FolioDomain
import SwiftUI

struct SemesterView: View {
    @State private var model: SemesterModel
    @Environment(\.openLink) private var openLink
    @State private var addingCourse = false
    @State private var confirmingTrim = false
    @State private var confirmingSource = false
    @State private var viewingFile: AdminFile?

    init(workspace: Workspace, semesterID: UUID) {
        _model = State(initialValue: SemesterModel(workspace: workspace, semesterID: semesterID))
    }

    func openCourse(_ id: UUID) { openLink(.course(id)) }

    var body: some View {
        if let semester = model.semester {
            let courses = model.courses(in: semester)
            Page {
                PageHeader(title: semester.title, subtitle: model.subtitle(semester))

                StatStrip(items: model.stats(semester))

                if let audio = model.audio { audioCard(audio) }

                Block(
                    title: String(localized: .semesterCourses), note: String(localized: .semesterCoursesNote),
                    trailing: { Button(.semesterCoursesAdd) { addingCourse = true }.buttonStyle(.ghost) }
                ) {
                    Card {
                        if courses.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .semesterCoursesEmpty)) } }
                        ForEach(Array(courses.enumerated()), id: \.element.id) { i, course in
                            CardRow(last: i == courses.count - 1) {
                                FoldingRow {
                                    Button {
                                        openCourse(course.id)
                                    } label: {
                                        courseLabel(
                                            mark: CourseMark(
                                                icon: course.file.course.icon, color: model.workspace.accent(course.id).color,
                                                font: Theme.Glyph.lineTitle, duotone: true),
                                            title: course.title, detail: model.detail(course))
                                    }
                                    .buttonStyle(.pointing(.plain))
                                } control: {
                                    gradeMenu(course.file.course)
                                }
                            }
                            .contextMenu { courseMenu(course) }
                        }
                    }
                }

                if semester.term == .credited { sourceBlock }
                if semester.term != .credited {
                    Block(String(localized: .semesterTimetable)) {
                        Timetable(model: model, layout: model.timetable(semester), today: model.markedWeekday(semester), open: open) {
                            timetableMenu($0)
                        }
                    }

                    Fold(wideFrom: 704, stackSpacing: Theme.Space.xl) {
                        examsBlock(courses).frame(maxWidth: .infinity, alignment: .topLeading)
                        Block(String(localized: .semesterPeriod)) {
                            Card {
                                FormRow(label: String(localized: .semesterStart)) { dateChip(semester, \.start) }
                                FormRow(label: String(localized: .semesterEnd)) { dateChip(semester, \.end) }
                                FormRow(
                                    label: String(localized: .semesterMidtermWeek), detail: String(localized: .semesterMidtermWeekDetail)
                                ) {
                                    examWeek(semester, \.midtermWeek, fallback: semester.defaultExamWeeks?.midterm)
                                }
                                FormRow(label: String(localized: .semesterFinalWeek), last: true) {
                                    examWeek(semester, \.finalWeek, fallback: semester.defaultExamWeeks?.final)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                                    Button(.commonOpen) { viewingFile = AdminFile(url: url) }.buttonStyle(.ghost)
                                }
                                .contentShape(.rect)
                                .contextMenu {
                                    Button(.commonOpen, systemImage: "doc.text.magnifyingglass") { viewingFile = AdminFile(url: url) }
                                    #if os(macOS)
                                    Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                                    Button(.commonShowInFinder, systemImage: "folder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    #endif
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(semester.title)
            .task(id: semester.id) {
                model.loadSource()
                await model.refreshAudio()
            }
            .sheet(item: $viewingFile) { AdminFileSheet(workspace: model.workspace, url: $0.url) }
            .sheet(isPresented: $addingCourse) {
                AddCourseSheet(workspace: model.workspace, semester: semester) { if let id = $0 { openCourse(id) } }
            }
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

    func courseMenu(_ course: LoadedCourse) -> some View { CourseMenu(courseId: course.id) }

    func open(_ course: Course) { openCourse(course.id) }

    var sourceBlock: some View {
        Block(String(localized: .semesterSource), note: String(localized: .semesterSourceNote)) {
            Card {
                FormRow(label: String(localized: .semesterSource), detail: model.sourceRefusal ?? model.sourceFolder, last: true) {
                    InlineField(String(localized: .semesterSourceExample), text: $model.source)
                    Button(.commonSave) { confirmingSource = true }.buttonStyle(.ghost).disabled(!model.canSaveSource)
                }
            }
        }
        .confirmationDialog(model.sourceConfirmation(), isPresented: $confirmingSource) {
            Button(.commonSave) { model.saveSource() }
        }
    }

    @ViewBuilder func timetableMenu(_ course: Course) -> some View {
        if let loaded = model.folderCourse(course) { courseMenu(loaded) }
    }

    func showExams(_ course: UUID) {
        openLink(.course(course, page: .exams), course: course)
    }

    func audioCard(_ audio: SemesterModel.AudioNotice) -> some View {
        NoticeCard(
            title: String(localized: .semesterAudioTitle(audio.count, audio.bytes.formatted(.byteCount(style: .file)))),
            detail: audio.kept > 0 ? String(localized: .semesterAudioDetailKept(audio.kept)) : String(localized: .semesterAudioDetail),
            systemImage: "waveform.badge.minus"
        ) {
            Button(.semesterAudioTrimEllipsis) { confirmingTrim = true }.buttonStyle(.pointing(.bordered))
        } rows: {
            ForEach(Array(audio.items.enumerated()), id: \.element.id) { i, item in
                CardRow(last: i == audio.items.count - 1) {
                    Text(item.course.title).lineLimit(1)
                    Spacer()
                    Text(.semesterAudioRow(item.count, item.bytes.formatted(.byteCount(style: .file))))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
            }
        }
        .confirmationDialog(model.trimConfirmation(), isPresented: $confirmingTrim) {
            Button(.semesterAudioTrim, role: .destructive) { Task { await model.trim() } }
        } message: {
            Text(.semesterAudioConfirmMessage)
        }
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
                            Text(start.formatted(.dateTime.weekday().hour().minute())).font(Theme.Typeface.caption).foregroundStyle(
                                Theme.Palette.textTertiary
                            ).monospacedDigit()
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
                    .opacity(start > now ? 1 : 0.6)
                    .opens { showExams(item.course.id) }
                    .contextMenu { ExamMenu(courseId: item.course.id, examId: item.exam.id) }
                }
            }
        }
    }

    @ViewBuilder func gradeMenu(_ course: Course) -> some View {
        let grades = model.grades(for: course)
        let selection = Binding(get: { course.finalGrade }, set: { model.setFinalGrade($0, of: course) })
        if grades.contains(where: { $0.points != nil }) {
            GradeSteps(selection: selection, grades: grades.map { ($0.id, $0.symbol, $0.points != nil) })
                .sensitive(.control)
        } else {
            StepToggle(
                selection: selection,
                options: [.init(value: nil, label: String(localized: .semesterGradeNone), tint: Theme.Palette.textTertiary)]
                    + grades.map {
                        .init(
                            value: $0.id, label: $0.symbol, tint: $0.countsInCredits ? Theme.Palette.success : Theme.Palette.textSecondary)
                    },
                ordered: false
            )
            .sensitive()
        }
    }

    func examWeek(_ semester: Semester, _ key: WritableKeyPath<Semester, Int?>, fallback: Int?) -> some View {
        ChoiceMenu(
            selection: Binding(get: { semester[keyPath: key] ?? fallback }, set: { model.setWeek(semester, key, to: $0) }),
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

private struct AdminFileSheet: View {
    let workspace: Workspace
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FileView(workspace: workspace, url: url)
                .environment(nil as CrumbTrail?)
                .navigationTitle(url.lastPathComponent)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(.commonClose) { dismiss() } } }
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 560, idealHeight: 760)
    }
}

private struct AdminFile: Identifiable {
    let url: URL
    var id: URL { url }
}
