import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

extension ReviewReason {
    var label: String {
        switch self {
        case .guessedWeek: String(localized: .reviewReasonGuessedWeek)
        case .unknownWeek: String(localized: .reviewReasonUnknownWeek)
        case .guessedNumber: String(localized: .reviewReasonGuessedNumber)
        case .unknownNumber: String(localized: .reviewReasonUnknownNumber)
        case .guessedExam: String(localized: .reviewReasonGuessedExam)
        case .pastExamNameKept: String(localized: .reviewReasonPastExamNameKept)
        case .guessedFolder: String(localized: .reviewReasonGuessedFolder)
        case .unknownFile: String(localized: .reviewReasonUnknownFile)
        case .unknownFolder: String(localized: .reviewReasonUnknownFolder)
        case .nameCollision: String(localized: .reviewReasonNameCollision)
        }
    }
}

/// People, the grading rules as written, the memo and the folder, at the bottom of the overview.
struct InfoBlocks: View {
    @Environment(\.accent) private var accent
    @Environment(\.personTarget) private var personTarget
    @Environment(\.openURL) private var openURL
    let course: LoadedCourse
    @State private var model: CourseInfoModel

    init(workspace: Workspace, course: LoadedCourse) {
        self.course = course
        _model = State(initialValue: CourseInfoModel(workspace: workspace))
    }

    var body: some View {
        let c = course.file.course
        let people = model.people(c)
        Group {
            Block(String(localized: .courseInfoPeople)) {
                Card {
                    if people.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .courseInfoNoPeople)) } }
                    ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                        CardRow(last: i == people.count - 1) {
                            // The name and its details open the person; the address beside them still writes mail.
                            Button { personTarget.wrappedValue = p.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(p.name)
                                        if let detail = model.detail(p) {
                                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        }
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textTertiary)
                                    Spacer(minLength: Theme.Space.m)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .help(Text(.courseInfoOpenPerson(p.name)))
                            if let url = model.mailURL(p) {
                                Link(p.email, destination: url).buttonStyle(.plain).foregroundStyle(accent.ink).pointingHand()
                            }
                        }
                        .contextMenu {
                            Button(.courseInfoOpenPerson(p.name), systemImage: "person") { personTarget.wrappedValue = p.id }
                            if let url = model.mailURL(p) {
                                Button(.courseInfoWriteMail, systemImage: "envelope") { openURL(url) }
                            }
                        }
                    }
                }
            }
            Block(String(localized: .courseInfoMemo)) {
                Card {
                    TextEditor(text: $model.memo)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(Theme.Space.m)
                    Theme.Palette.lineSoft.frame(height: 1)
                    CardRow(last: true) {
                        Spacer()
                        Button(.courseInfoSaveMemo) { model.saveMemo(course.id) }
                            .buttonStyle(.pointing(.borderedProminent))
                            .disabled(model.memo == c.memo)
                    }
                }
            }
            Block(String(localized: .courseInfoFolder)) {
                Card {
                    FormRow(label: course.store.url.lastPathComponent, detail: course.store.url.deletingLastPathComponent().path, last: true) {
                        #if os(macOS)
                        Button(.commonShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                        #endif
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button(.commonShowInFinder, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                    }
                    #endif
                }
            }
        }
        .onAppear { model.memo = c.memo }
        // A memo saved elsewhere (another device, the sync) replaces the shown one unless it is being edited here.
        .onChange(of: c.memo) { old, new in if model.memo == old { model.memo = new } }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MaterialRole {
    var label: String {
        switch self {
        case .syllabus: String(localized: .materialRoleSyllabus)
        case .lecture: String(localized: .materialRoleLecture)
        case .exercise: String(localized: .materialRoleExercise)
        case .textbook: String(localized: .materialRoleTextbook)
        case .assignment: String(localized: .materialRoleAssignment)
        case .lab: String(localized: .materialRoleLab)
        case .pastExam: String(localized: .materialRolePastExam)
        case .examPrep: String(localized: .materialRoleExamPrep)
        case .archive: String(localized: .materialRoleArchive)
        case .other: String(localized: .materialRoleOther)
        }
    }
}

extension AssignmentStatus {
    @MainActor static let steps: [StepToggle<AssignmentStatus>.Option] = [
        .init(value: .todo, label: String(localized: .assignmentStatusTodo), tint: Theme.Palette.textSecondary),
        .init(value: .doing, label: String(localized: .assignmentStatusDoing), tint: Theme.Palette.warning),
        .init(value: .submitted, label: String(localized: .assignmentStatusSubmitted), tint: Theme.Palette.success),
        .init(value: .graded, label: String(localized: .assignmentStatusGraded), tint: Theme.Series.one),
    ]

    var label: String {
        switch self {
        case .todo: String(localized: .assignmentStatusTodo)
        case .doing: String(localized: .assignmentStatusDoing)
        case .submitted: String(localized: .assignmentStatusSubmitted)
        case .graded: String(localized: .assignmentStatusGraded)
        }
    }

    /// The circle a todo app draws: empty, half full, checked, then the seal once a score is back.
    /// `AssignmentStatusIcon` draws doing itself; this symbol is for menus.
    var symbol: String {
        switch self {
        case .todo: "circle"
        case .doing: "circle.lefthalf.filled"
        case .submitted: "checkmark.circle.fill"
        case .graded: "checkmark.seal.fill"
        }
    }

    @MainActor var tint: Color { Self.steps.first { $0.value == self }?.tint ?? Theme.Palette.textTertiary }
}

struct AssignmentStatusIcon: View {
    let status: AssignmentStatus
    var tint: Color?
    var size: CGFloat = 20

    var body: some View {
        // The half-done ring's measurements are for 20pt; they scale with the symbol.
        let k = size / 20
        Group {
            if status == .doing {
                // circle.lefthalf.filled runs the fill into the ring and reads as a blot; a gap keeps it a ring that is half done.
                // 20 and 1.7 are SF `circle` at 20pt, measured, so it lines up with the other states' symbols.
                ZStack {
                    Circle().strokeBorder(lineWidth: 1.7 * k)
                    HalfDisc(round: k).fill()
                        .overlay { HalfDisc(round: k).stroke(style: StrokeStyle(lineWidth: 2 * k, lineJoin: .round)) }
                        .padding(2.9 * k)
                }
                .frame(width: size, height: size)
            } else {
                Image(systemName: status.symbol)
                    .font(.system(size: size)) // design: one-off, the status symbol is the row's button
            }
        }
        .foregroundStyle(tint ?? (status == .todo ? Theme.Palette.textTertiary : status.tint))
        .frame(width: size + 4, height: size + 4)
    }
}

/// The right half of the rect's circle, drawn `round` short on every side so a round-joined stroke of twice that
/// brings it back to full size with soft corners. Rounding by shrinking only the flat side would push the shape right.
private struct HalfDisc: Shape {
    let round: CGFloat

    func path(in rect: CGRect) -> Path {
        let rho = rect.width / 2 - round, theta = acos(round / rho)
        var p = Path()
        p.addRelativeArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rho, startAngle: .radians(-theta), delta: .radians(2 * theta))
        p.closeSubpath()
        return p
    }
}

extension ExamKind {
    var label: String {
        switch self {
        case .midterm: String(localized: .examKindMidterm)
        case .final: String(localized: .examKindFinal)
        case .quiz: String(localized: .examKindQuiz)
        case .other: String(localized: .examKindOther)
        }
    }
}

/// Edits course.json. The folder name follows the title, main code and number, so saving a change to those renames it.
struct EditCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        let course = model.course
        SheetForm(title: String(localized: .courseEdit), confirm: String(localized: .commonSave), disabled: !model.canSave,
                  note: model.note, carded: false, width: 560) {
            Block(String(localized: .courseEditCourse)) {
                Card {
                    FormRow(label: String(localized: .courseEditName)) { InlineField(String(localized: .courseEditNameExample), text: $model.title) }
                    // Prefix and number side by side, as the course reads: GS2004-02.
                    FormRow(label: String(localized: .courseEditCode), detail: model.codeDetail) {
                        CodesMenu(codes: $model.codes)
                        TextField("2004-02", text: $model.number).pill(width: 100)
                    }
                    if model.codes.count > 1 {
                        FormRow(label: String(localized: .courseEditMainCode)) {
                            ChoiceMenu(selection: Binding(get: { model.codes[0] }, set: model.makeMain), options: model.codeOptions)
                        }
                    }
                    FormRow(label: String(localized: .courseEditCredits)) { CreditsField(credits: $model.credits) }
                    FormRow(label: String(localized: .courseEditGrading), last: true) {
                        ChoiceMenu(selection: $model.mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
                    }
                }
            }
            ClassTimesBlock(schedule: $model.schedule)
            Block(String(localized: .courseEditManage)) {
                Card {
                    FormRow(label: String(localized: .courseInfoPeople)) {
                        SearchMultiSelect(selection: $model.people, options: model.peopleOptions, placeholder: model.peoplePlaceholder)
                    }
                    FormRow(label: String(localized: .courseEditCategories), detail: String(localized: .courseEditCategoriesDetail)) {
                        CategoryMenu(selection: $model.categories, course: model.draft)
                    }
                    if model.showsSharing {
                        FormRow(label: String(localized: .courseEditSharing), detail: String(localized: .courseEditSharingDetail)) { Switch(isOn: $model.sharingApproved) }
                    }
                    FormRow(label: String(localized: .courseEditReviews), detail: String(localized: .courseEditReviewsDetail)) { Switch(isOn: $model.reviews) }
                    FormRow(label: String(localized: .courseEditIcon), detail: String(localized: .courseEditIconDetail)) {
                        CourseIconPicker(icon: $model.icon, color: model.workspace.accent(course.id, token: model.color).color)
                    }
                    FormRow(label: String(localized: .courseEditColor), last: true) {
                        HStack(spacing: Theme.Space.s) {
                            if model.color.isEmpty {
                                Text(.courseEditColorAuto).foregroundStyle(Theme.Palette.textTertiary)
                            } else {
                                Button(.courseEditColorMakeAuto) { model.color = "" }.buttonStyle(.ghost)
                            }
                            ColorPicker(String(localized: .courseEditColorPicker), selection: Binding(
                                get: { model.workspace.accent(course.id, token: model.color).color },
                                set: { model.color = CourseAccent.token($0.resolve(in: environment)) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                    }
                }
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
    }
}

/// The weekly class times, one row each. The next lecture is suggested from these.
struct ClassTimesBlock: View {
    @Binding var schedule: [ClassTime]

    var body: some View {
        Block(title: String(localized: .classTimesTitle), note: String(localized: .classTimesNote), trailing: {
            Button(.classTimesAdd, systemImage: "plus") { schedule.append(ClassTime(weekday: 1, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)) }
                .buttonStyle(.ghost)
        }) {
            Card {
                if schedule.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .classTimesEmpty)) } }
                ForEach(schedule.indices, id: \.self) { i in
                    let slot = schedule[i]
                    CardRow(last: i == schedule.count - 1) {
                        ChoiceMenu(selection: $schedule.element(at: i, fallback: slot).weekday,
                                   options: (1...7).map { ($0, String(localized: .classTimesWeekday(ClassTime.weekdayNames[$0 - 1]))) })
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).startMinute)
                        Text("–").foregroundStyle(Theme.Palette.textTertiary)
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).endMinute)
                        Spacer(minLength: Theme.Space.m)
                        TextField(String(localized: .classTimesRoom), text: $schedule.element(at: i, fallback: slot).room).pill(width: 130)
                        Button(.commonDelete, systemImage: "minus.circle") { schedule.remove(at: i) }
                            .buttonStyle(.ghostIcon).tint(Theme.Palette.danger)
                    }
                }
            }
        }
    }
}

/// Only the class times, for the sessions page.
struct ClassTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        // The course as the heading: the block below already says 수업 시간, and twice in a row read as a mistake.
        SheetForm(title: model.course.title, confirm: String(localized: .commonSave), disabled: model.badTime,
                  note: model.timesNote, carded: false, width: 560) {
            ClassTimesBlock(schedule: $model.schedule)
        } onConfirm: {
            model.confirmSchedule()
            dismiss()
        }
    }
}

/// Credits as a typed number; half credits exist, so a fixed menu of whole numbers won't do.
struct CreditsField: View {
    @Binding var credits: Double?

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("3", value: $credits, format: .number).pill(width: 56).multilineTextAlignment(.trailing)
            Text(.courseEditCredits).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// Cross-listed codes in order; the first is the main code.
struct CodesMenu: View {
    @Environment(Workspace.self) private var workspace
    @Binding var codes: [UUID]

    var body: some View {
        let all = workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
        SearchMultiSelect(selection: $codes, options: all.map { PickOption(id: $0.id, title: "\($0.prefix) · \($0.department)", detail: $0.program) },
                          summary: codes.isEmpty ? nil : codes.compactMap { id in all.first { $0.id == id }?.prefix }.joined(separator: " · "))
    }
}
