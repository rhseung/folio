import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

extension ReviewReason {
    var label: String {
        switch self {
        case .guessedWeek: "주차 추정"
        case .unknownWeek: "주차 모름"
        case .guessedNumber: "과제 번호 추정"
        case .unknownNumber: "과제 번호 모름"
        case .guessedExam: "대상 시험 추정"
        case .pastExamNameKept: "족보 이름 유지"
        case .guessedFolder: "위치 추정"
        case .unknownFile: "분류 불명"
        case .unknownFolder: "대응 폴더 없음"
        case .nameCollision: "이름 충돌"
        }
    }
}

/// People, the grading rules as written, the memo and the folder, at the bottom of the overview.
struct InfoBlocks: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.personTarget) private var personTarget
    @Environment(\.openURL) private var openURL
    let course: LoadedCourse
    @State private var memo = ""

    var body: some View {
        let c = course.file.course
        let people = c.instructorIds.compactMap { id in workspace.catalog.people.first { $0.id == id } }
        Group {
            Block("교수와 조교") {
                Card {
                    if people.isEmpty { CardRow(last: true) { EmptyLine("등록된 사람이 없습니다") } }
                    ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                        CardRow(last: i == people.count - 1) {
                            // The name and its details open the person; the address beside them still writes mail.
                            Button { personTarget.wrappedValue = p.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(p.name)
                                        if let detail = [p.office, p.officeHours].filter({ !$0.isEmpty }).joined(separator: " · ").nilIfEmpty {
                                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        }
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textTertiary)
                                    Spacer(minLength: Theme.Space.m)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .help("\(p.name) 페이지 열기")
                            if let url = workspace.mailURL(to: p.email) {
                                Link(p.email, destination: url).buttonStyle(.plain).foregroundStyle(accent.ink).pointingHand()
                            }
                        }
                        .contextMenu {
                            Button("\(p.name) 페이지 열기", systemImage: "person") { personTarget.wrappedValue = p.id }
                            if let url = workspace.mailURL(to: p.email) {
                                Button("메일 쓰기", systemImage: "envelope") { openURL(url) }
                            }
                        }
                    }
                }
            }
            Block("메모") {
                Card {
                    TextEditor(text: $memo)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(Theme.Space.m)
                    Theme.Palette.lineSoft.frame(height: 1)
                    CardRow(last: true) {
                        Spacer()
                        Button("메모 저장") { workspace.run(CourseSet(course: course.id, [.memo(memo)])) }
                            .buttonStyle(.pointing(.borderedProminent))
                            .disabled(memo == c.memo)
                    }
                }
            }
            Block("폴더") {
                Card {
                    FormRow(label: course.store.url.lastPathComponent, detail: course.store.url.deletingLastPathComponent().path, last: true) {
                        #if os(macOS)
                        Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                        #endif
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button("Finder에서 보기", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                    }
                    #endif
                }
            }
        }
        .onAppear { memo = c.memo }
        // A memo saved elsewhere (another device, the sync) replaces the shown one unless it is being edited here.
        .onChange(of: c.memo) { old, new in if memo == old { memo = new } }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MaterialRole {
    var label: String {
        switch self {
        case .syllabus: "강의계획서"
        case .lecture: "강의 자료"
        case .exercise: "연습 문제"
        case .textbook: "교재"
        case .assignment: "과제"
        case .lab: "실험"
        case .pastExam: "족보"
        case .examPrep: "시험 대비"
        case .archive: "이전 필기"
        case .other: "기타"
        }
    }
}

extension AssignmentStatus {
    @MainActor static let steps: [StepToggle<AssignmentStatus>.Option] = [
        .init(value: .todo, label: "할 일", tint: Theme.Palette.textSecondary),
        .init(value: .doing, label: "하는 중", tint: Theme.Palette.warning),
        .init(value: .submitted, label: "제출", tint: Theme.Palette.success),
        .init(value: .graded, label: "채점됨", tint: Theme.Series.one),
    ]

    var label: String {
        switch self {
        case .todo: "할 일"
        case .doing: "하는 중"
        case .submitted: "제출"
        case .graded: "채점됨"
        }
    }

    /// The circle a todo app draws: empty, half full, checked, then the seal once a score is back.
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

extension ExamKind {
    var label: String {
        switch self {
        case .midterm: "중간고사"
        case .final: "기말고사"
        case .quiz: "퀴즈"
        case .other: "기타"
        }
    }
}

/// Edits course.json. The folder name follows the title, main code and number, so saving a change to those renames it.
struct EditCourseSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment
    let course: LoadedCourse
    @State private var title: String
    @State private var codes: [UUID]
    @State private var number: String
    @State private var credits: Double?
    @State private var mode: GradingMode
    @State private var people: [UUID]
    @State private var categories: [UUID]
    @State private var color: String
    @State private var icon: String?
    @State private var reviews: Bool
    @State private var sharingApproved: Bool
    @State private var schedule: [ClassTime]

    init(course: LoadedCourse) {
        self.course = course
        let c = course.file.course
        _title = State(initialValue: c.title)
        _codes = State(initialValue: c.codes)
        _number = State(initialValue: c.number)
        _credits = State(initialValue: c.credits)
        _mode = State(initialValue: c.gradingMode)
        _people = State(initialValue: c.instructorIds)
        _categories = State(initialValue: c.categoryIds)
        _color = State(initialValue: c.color)
        _icon = State(initialValue: c.icon)
        _reviews = State(initialValue: c.reviews != false)
        _sharingApproved = State(initialValue: c.sharingApproved == true)
        _schedule = State(initialValue: c.schedule)
    }

    /// The course as the form now has it, for what its codes and approval let it share.
    var draft: Course {
        var c = course.file.course
        c.codes = codes
        c.sharingApproved = sharingApproved ? true : nil
        return c
    }

    var body: some View {
        let catalog = workspace.catalog.people.sorted { $0.name < $1.name }
        let folder = workspace.folderName(title: title, codes: codes, number: number)
        let current = course.store.url.lastPathComponent
        let badTime = schedule.contains { $0.endMinute <= $0.startMinute }
        SheetForm(title: "과목 편집", confirm: "저장", disabled: (credits ?? -1) < 0 || folder == nil || badTime,
                  note: folder == nil ? "강의 코드와 번호(예: 4207-01), 이름을 넣어야 폴더 이름이 정해집니다"
                      : badTime ? "수업이 끝나는 시간이 시작 시간보다 늦어야 합니다"
                      : folder == current ? nil : "저장하면 폴더 이름을 ‘\(current)’에서 ‘\(folder!)’로 바꿉니다", carded: false, width: 560) {
            Block("과목") {
                Card {
                    FormRow(label: "이름") { InlineField("예: 그래프 이론", text: $title) }
                    // Prefix and number side by side, as the course reads: GS2004-02.
                    FormRow(label: "강의 코드", detail: codes.count > 1 ? "교차 개설: 첫 코드를 폴더 이름에 씁니다" : nil) {
                        CodesMenu(codes: $codes)
                        TextField("2004-02", text: $number).pill(width: 100)
                    }
                    if codes.count > 1 {
                        FormRow(label: "대표 코드") {
                            ChoiceMenu(selection: Binding(get: { codes[0] }, set: { id in codes.removeAll { $0 == id }; codes.insert(id, at: 0) }),
                                       options: codes.map { id in (id, workspace.catalog.codes.first { $0.id == id }?.prefix ?? "?") })
                        }
                    }
                    FormRow(label: "학점") { CreditsField(credits: $credits) }
                    FormRow(label: "평가 방식", last: true) {
                        ChoiceMenu(selection: $mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
                    }
                }
            }
            ClassTimesBlock(schedule: $schedule)
            Block("관리") {
                Card {
                    FormRow(label: "교수와 조교") {
                        SearchMultiSelect(selection: $people, options: catalog.map { PickOption(id: $0.id, title: $0.name, detail: [$0.role.label, $0.email].filter { !$0.isEmpty }.joined(separator: " · ")) },
                                          placeholder: catalog.isEmpty ? "사이드바의 교수와 조교에서 먼저 추가하세요" : "고르기")
                    }
                    FormRow(label: "세부 분류", detail: "졸업 요건에서 이 과목이 들어갈 곳") { CategoryMenu(selection: $categories, course: draft) }
                    if workspace.requirementCatalog.categories.contains(where: { $0.maxSharedCredits != nil }) {
                        FormRow(label: "학과 인정 과목", detail: "강의 공유 코드가 없어도 전공과 복수전공에 함께 셉니다") { Switch(isOn: $sharingApproved) }
                    }
                    FormRow(label: "복습", detail: "끄면 오늘 복습과 복습 노트 알림에서 빠집니다") { Switch(isOn: $reviews) }
                    FormRow(label: "아이콘", detail: "사이드바, 과목 열, 위치 표시에 씁니다") {
                        CourseIconPicker(icon: $icon, color: workspace.accent(course.id, token: color).color)
                    }
                    FormRow(label: "색", last: true) {
                        HStack(spacing: Theme.Space.s) {
                            if color.isEmpty {
                                Text("자동").foregroundStyle(Theme.Palette.textTertiary)
                            } else {
                                Button("자동으로") { color = "" }.buttonStyle(.ghost)
                            }
                            ColorPicker("과목 색", selection: Binding(
                                get: { workspace.accent(course.id, token: color).color },
                                set: { color = CourseAccent.token($0.resolve(in: environment)) }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                    }
                }
            }
        } onConfirm: {
            guard let credits else { return }
            let c = course.file.course
            if title != c.title || codes != c.codes || number != c.number {
                guard workspace.run(CourseRename(course: course.id, title: title, codes: codes, number: number)) != nil else { return }
            }
            workspace.run(CourseSet(course: course.id, [.credits(credits), .gradingMode(mode), .instructors(people), .categories(categories),
                                                       .color(color), .icon(icon), .schedule(schedule), .reviews(reviews), .sharingApproved(sharingApproved)]))
            dismiss()
        }
    }
}

/// The weekly class times, one row each. The next lecture is suggested from these.
struct ClassTimesBlock: View {
    @Binding var schedule: [ClassTime]

    var body: some View {
        Block(title: "수업 시간", note: "다음 강의를 제안할 때 씁니다", trailing: {
            Button("시간 추가", systemImage: "plus") { schedule.append(ClassTime(weekday: 1, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)) }
                .buttonStyle(.ghost)
        }) {
            Card {
                if schedule.isEmpty { CardRow(last: true) { EmptyLine("수업 시간이 없습니다") } }
                ForEach(schedule.indices, id: \.self) { i in
                    let slot = schedule[i]
                    CardRow(last: i == schedule.count - 1) {
                        ChoiceMenu(selection: $schedule.element(at: i, fallback: slot).weekday, options: (1...7).map { ($0, "\(ClassTime.weekdayNames[$0 - 1])요일") })
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).startMinute)
                        Text("–").foregroundStyle(Theme.Palette.textTertiary)
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).endMinute)
                        Spacer(minLength: Theme.Space.m)
                        TextField("강의실", text: $schedule.element(at: i, fallback: slot).room).pill(width: 130)
                        Button("삭제", systemImage: "minus.circle") { schedule.remove(at: i) }
                            .buttonStyle(.ghostIcon).tint(Theme.Palette.danger)
                    }
                }
            }
        }
    }
}

/// Only the class times, for 바꾸기 on the sessions page.
struct ClassTimesSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State private var schedule: [ClassTime]

    init(course: LoadedCourse) {
        self.course = course
        _schedule = State(initialValue: course.file.course.schedule)
    }

    var body: some View {
        let badTime = schedule.contains { $0.endMinute <= $0.startMinute }
        // The course as the heading: the block below already says 수업 시간, and twice in a row read as a mistake.
        SheetForm(title: course.title, confirm: "저장", disabled: badTime,
                  note: badTime ? "수업이 끝나는 시간이 시작 시간보다 늦어야 합니다" : nil, carded: false, width: 560) {
            ClassTimesBlock(schedule: $schedule)
        } onConfirm: {
            workspace.run(CourseSet(course: course.id, [.schedule(schedule)]))
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
            Text("학점").foregroundStyle(Theme.Palette.textSecondary)
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
