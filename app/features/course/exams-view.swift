import FolioActions
import FolioDomain
import SwiftUI

/// Coming exams first, each with its facts, scope and plan; finished ones below as single rows (docs/SPEC.md "시험").
struct ExamsView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let openNote: (UUID) -> Void
    @State private var editing: Exam?
    @State private var deleting: Exam?
    @State private var notes: [UUID: UUID] = [:]
    @State private var done: Set<UUID> = []

    static let dateColumn: CGFloat = 104

    var body: some View {
        let now = Date.now
        let exams = course.file.exams.sorted { ($0.start ?? .distantFuture, $0.title) < ($1.start ?? .distantFuture, $1.title) }
        let coming = exams.filter { !isOver($0, now: now) }
        let past = Array(exams.filter { isOver($0, now: now) }.reversed())
        let states = workspace.reviewStates(of: course.id, now: now)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "시험", subtitle: exams.isEmpty ? "등록한 시험이 없습니다"
                           : ([coming.isEmpty ? "예정된 시험 없음" : "예정 \(coming.count)개"] + (past.isEmpty ? [] : ["지난 시험 \(past.count)개"])).joined(separator: " · "))
                Spacer()
                Button("시험 추가") { editing = Exam(device: workspace.device, at: .now, kind: .midterm, title: "", start: defaultStart) }
                    .buttonStyle(.pointing(.borderedProminent))
            }
            if exams.isEmpty {
                Card { CardRow(last: true) { EmptyLine("시험을 추가하면 일시와 범위, 종합 정리 노트, 시험까지의 계획을 여기서 봅니다.") } }
            }
            ForEach(coming) { exam in
                section(exam, states: states)
            }
            if !past.isEmpty {
                Block("지난 시험", note: "\(past.count)") {
                    Card {
                        ForEach(Array(past.enumerated()), id: \.element.id) { i, exam in
                            CardRow(last: i == past.count - 1) { pastRow(exam) }
                                .contentShape(.rect)
                                .contextMenu { actions(exam) }
                                .fileDrop { drop($0, on: exam) }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { ExamEditor(course: course, exam: $0) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.editExam, initial: true) { _, on in editing = on ? course.file.exams.first : nil }
        #endif
        .confirmationDialog("\(deleting?.title ?? "")을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { exam in
            Button("삭제", role: .destructive) { workspace.run(ExamRemove(course: course.id, exam: exam.id)) }
        } message: { _ in
            Text("시험 기록과 계획을 지웁니다. 시험 폴더와 파일은 그대로 둡니다.")
        }
        .task(id: course.id) {
            notes = workspace.examSummaryNotes(course: course.id)
            done = workspace.donePlanItems(in: [course.id])
        }
    }

    var defaultStart: Date {
        let c = workspace.calendar
        return c.date(byAdding: .hour, value: 24 + 9, to: c.startOfDay(for: .now)) ?? .now
    }

    /// Over once it has ended, not when the day turns: an exam that finished this morning is no longer coming.
    func isOver(_ exam: Exam, now: Date) -> Bool {
        if let end = exam.end { return end < now }
        return exam.start.map { workspace.days(to: $0) < 0 } ?? false
    }

    func drop(_ urls: [URL], on exam: Exam) {
        if let folder = MaterialIntake.folder(of: exam, among: course.file.exams) { workspace.importFiles(urls, into: folder, course: course.id) }
    }

    func fileCount(_ folder: String) -> Int {
        course.file.materials.filter { $0.path.hasPrefix(folder + "/") && $0.status != .ignored }.count
    }

    /// When and where with the summary note, the scope as it stands in review, the folder, then the plan.
    func section(_ exam: Exam, states: [UUID: ReviewState]) -> some View {
        Block(title: exam.title, note: exam.kind.label) {
            if let start = exam.start { DdayChip(days: max(workspace.days(to: start), 0)) }
        } content: {
            Card {
                CardRow {
                    when(exam, muted: false)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.m) {
                            fact("mappin.and.ellipse", exam.location, empty: "장소 미정")
                            // Empty means not entered yet, not that nothing is allowed.
                            if !exam.allowed.isEmpty { fact("doc.text", exam.allowed, empty: "") }
                        }
                        if !exam.memo.isEmpty {
                            Text(exam.memo).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    summaryButton(exam)
                    menu(exam)
                }
                scope(exam, states: states)
                if let folder = MaterialIntake.folder(of: exam, among: course.file.exams) {
                    let count = fileCount(folder)
                    CardRow(last: true) {
                        Label(folder, systemImage: "folder").foregroundStyle(Theme.Palette.textSecondary)
                        Text(count == 0 ? "파일을 이 카드에 끌어다 놓으면 이 폴더에 넣습니다" : "파일 \(count)개")
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                        Spacer(minLength: 0)
                    }
                }
            }
            .contextMenu { actions(exam) }
            .fileDrop { drop($0, on: exam) }
            ExamPlanCard(course: course, exam: exam, done: $done)
        }
    }

    /// Date over weekday and time, in a fixed column as the session list has.
    func when(_ exam: Exam, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(exam.start?.formatted(.dateTime.month().day()) ?? "일시 미정").font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(muted || exam.start == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
            if let start = exam.start {
                Text(start.formatted(.dateTime.weekday()) + " " + (exam.end.map { TimeMenu.range(minute(start), minute($0)) } ?? TimeMenu.label(minute(start))))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit().lineLimit(1)
            }
        }
        .frame(width: Self.dateColumn, alignment: .leading)
    }

    func minute(_ date: Date) -> Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The scope's top units numbered, each marked with how its review stands; sub-units count toward the meter only.
    @ViewBuilder func scope(_ exam: Exam, states: [UUID: ReviewState]) -> some View {
        let units = UnitTree.outline(course.file.units).map(\.unit).filter { exam.scopeUnitIds.contains($0.id) }
        let ids = Set(units.map(\.id))
        let tops = units.filter { $0.parentId.map { !ids.contains($0) } ?? true }
        let today = workspace.today
        // A state exists as soon as a class covered the unit, so having one says nothing about reviewing it.
        let onTrack = units.filter { u in states[u.id].map { !$0.writeNoteFirst && ($0.due.map { $0 >= today } ?? true) } ?? false }.count
        if units.isEmpty {
            CardRow {
                Text("범위").font(Theme.Typeface.bodyStrong)
                Text(exam.scopeText.isEmpty ? "범위 단원을 고르지 않았습니다" : exam.scopeText)
                    .foregroundStyle(exam.scopeText.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
                Spacer(minLength: 0)
                if !course.file.units.isEmpty { Button("범위 고르기") { editing = exam }.buttonStyle(.ghost) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("범위").font(Theme.Typeface.bodyStrong)
                    Text("단원 \(units.count)개" + (exam.scopeText.isEmpty ? "" : " · \(exam.scopeText)"))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    Spacer(minLength: Theme.Space.m)
                    Text("제때 복습 \(onTrack)/\(units.count)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                        .help("복습 노트가 있고 복습일이 지나지 않은 단원")
                }
                Meter(value: Double(onTrack) / Double(units.count), height: 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.l, alignment: .leading)], alignment: .leading, spacing: 0) {
                    ForEach(Array(tops.enumerated()), id: \.element.id) { i, unit in
                        let children = units.filter { $0.parentId == unit.id }.count
                        HStack(spacing: Theme.Space.s) {
                            Text("\(i + 1)").font(Theme.Typeface.label).monospacedDigit().foregroundStyle(accent.ink)
                                .frame(width: 20, alignment: .trailing)
                            Text(unit.title).lineLimit(1)
                            if children > 0 { Text("+\(children)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit() }
                            Spacer(minLength: 0)
                            ReviewDot(state: states[unit.id], today: today)
                        }
                        .padding(.vertical, Theme.Space.tight)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .overlay(alignment: .bottom) { Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l) }
        }
    }

    /// A finished exam in one row: its facts in a line, the summary note still a click away.
    func pastRow(_ exam: Exam) -> some View {
        let scoped = exam.scopeUnitIds.count
        let checked = exam.plan.filter { done.contains($0.id) }.count
        let files = MaterialIntake.folder(of: exam, among: course.file.exams).map { fileCount($0) } ?? 0
        let facts = [exam.kind.label]
            + (scoped > 0 ? ["단원 \(scoped)개"] : exam.scopeText.isEmpty ? [] : [exam.scopeText])
            + (exam.location.isEmpty ? [] : [exam.location])
            + (files > 0 ? ["파일 \(files)개"] : [])
            + (exam.plan.isEmpty ? [] : ["계획 \(checked)/\(exam.plan.count)"])
        return Group {
            when(exam, muted: true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(exam.title).font(Theme.Typeface.bodyStrong)
                Text(facts.joined(separator: " · ")).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            summaryButton(exam)
            menu(exam)
        }
    }

    func summaryButton(_ exam: Exam) -> some View {
        Button(notes[exam.id] == nil ? "종합 정리 만들기" : "종합 정리 열기") { openSummary(exam) }
        .buttonStyle(.pointing(.bordered))
        .help(notes[exam.id] == nil ? "범위 단원으로 템플릿에서 노트를 만듭니다" : "시험 종합 정리 노트")
    }

    func openSummary(_ exam: Exam) {
        if let id = workspace.openExamSummary(exam, course: course.id) {
            notes[exam.id] = id
            openNote(id)
        }
    }

    /// The ⋯ menu and the right-click menu, so both offer the same things.
    @ViewBuilder func actions(_ exam: Exam) -> some View {
        Button(notes[exam.id] == nil ? "종합 정리 만들기" : "종합 정리 열기") { openSummary(exam) }
        Button("편집…") { editing = exam }
        Divider()
        Button("삭제…", role: .destructive) { deleting = exam }
    }

    func menu(_ exam: Exam) -> some View {
        Menu {
            actions(exam)
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless).pointingHand()
        .fixedSize()
        .help("종합 정리, 편집, 삭제")
    }

    func fact(_ symbol: String, _ text: String, empty: String) -> some View {
        Label(text.isEmpty ? empty : text, systemImage: symbol)
            .font(Theme.Typeface.caption).lineLimit(1)
            .foregroundStyle(text.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
    }
}

/// Dated to-dos until the exam. Checking one appends a `plan_check` event; course.json only holds the items.
struct ExamPlanCard: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let exam: Exam
    @Binding var done: Set<UUID>
    @State private var day = Date.now
    @State private var title = ""
    @State private var unit: UUID?

    var body: some View {
        let items = exam.plan.sorted { ($0.day, $0.title) < ($1.day, $1.title) }
        let today = workspace.today
        let outline = UnitTree.outline(course.file.units)
        let scoped = outline.filter { exam.scopeUnitIds.contains($0.unit.id) }
        Card {
            CardRow {
                Text("시험 계획").font(Theme.Typeface.bodyStrong)
                Text(items.isEmpty ? "날짜별 할 일을 넣으면 그날 오늘 화면에도 나옵니다" : "\(items.filter { done.contains($0.id) }.count)/\(items.count) 완료")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let on = done.contains(item.id)
                CardRow {
                    CheckCircle(on: on) { toggle(item.id) }.help(on ? "완료 취소" : "완료")
                    // The day once per run of items, so the list reads as a timeline.
                    Text(i == 0 || items[i - 1].day != item.day ? dayLabel(item.day, today: today) : "")
                        .font(Theme.Typeface.caption.weight(item.day == today ? .semibold : .regular)).monospacedDigit()
                        .foregroundStyle(on ? Theme.Palette.textTertiary : item.day < today ? Theme.Palette.danger
                                         : item.day == today ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .frame(width: ExamsView.dateColumn, alignment: .leading)
                    Text(item.title).lineLimit(1)
                        .strikethrough(on, color: Theme.Palette.textTertiary)
                        .foregroundStyle(on ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let target = item.target, let t = course.file.units.first(where: { $0.id == target.id }) {
                        Text(t.title).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { remove(item.id) } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.ghost)
                    .help("항목 삭제")
                }
                .contentShape(.rect)
                .contextMenu {
                    Button(on ? "완료 취소" : "완료") { toggle(item.id) }
                    Divider()
                    Button("항목 삭제", role: .destructive) { remove(item.id) }
                }
            }
            CardRow(last: true) {
                DateChip(date: $day, showsTime: false)
                TextField("할 일", text: $title).textFieldStyle(.plain).onSubmit(add)
                // Scope units first: a plan is about what the exam covers.
                SearchSelect(selection: $unit, options: [PickOption(id: UUID?.none, title: "대상 없음")]
                             + (scoped.isEmpty ? outline : scoped).map { PickOption(id: Optional($0.unit.id), title: $0.unit.title, depth: scoped.isEmpty ? $0.depth : 0) })
                Button("추가", action: add).buttonStyle(.pointing(.bordered)).disabled(!workspace.can(item))
            }
        }
        .onAppear { day = workspace.today.date(in: workspace.calendar) ?? .now }
    }

    var item: ExamPlanAdd {
        ExamPlanAdd(course: course.id, exam: exam.id, title: title.trimmingCharacters(in: .whitespaces), day: LocalDate(day, in: workspace.calendar), unit: unit)
    }

    func add() {
        guard workspace.run(item) != nil else { return }
        title = ""
    }

    func toggle(_ id: UUID) {
        let new = !done.contains(id)
        workspace.setPlanItem(id, done: new, course: course.id)
        if new { done.insert(id) } else { done.remove(id) }
    }

    func remove(_ id: UUID) {
        workspace.run(ExamPlanRemove(course: course.id, exam: exam.id, item: id))
    }

    func dayLabel(_ day: LocalDate, today: LocalDate) -> String {
        if day == today { return "오늘" }
        return day.date(in: workspace.calendar)?.formatted(.dateTime.month().day().weekday()) ?? day.description
    }
}


/// Adds or edits one exam on a draft; nothing is saved until confirmed.
struct ExamEditor: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State private var draft: Exam

    init(course: LoadedCourse, exam: Exam) {
        self.course = course
        self._draft = State(initialValue: exam)
    }

    var isNew: Bool { !course.file.exams.contains { $0.id == draft.id } }

    /// `Midterm`, `Quiz2`: the folder name, so the record and its folder read the same.
    var defaultTitle: String {
        let number = draft.kind == .quiz ? course.file.exams.filter { $0.kind == .quiz }.count + 1 : nil
        return draft.kind.folderName(number: number) ?? draft.kind.label
    }

    var endsBeforeStart: Bool {
        guard let start = draft.start, let end = draft.end else { return false }
        return end <= start
    }

    var body: some View {
        let units = UnitTree.outline(course.file.units)
        SheetForm(title: isNew ? "시험 추가" : "\(draft.title) 편집", confirm: isNew ? "추가" : "저장", disabled: (!isNew && draft.title.isEmpty) || endsBeforeStart,
                  note: isNew ? draft.kind.folderName().map { _ in "시험 폴더 Exams/\(defaultTitle)도 만듭니다" } : nil, carded: false, width: 560) {
            Block("시험") {
                Card {
                    FormRow(label: "종류") { ChoiceMenu(selection: $draft.kind, options: [ExamKind.midterm, .final, .quiz, .other].map { ($0, $0.label) }) }
                    FormRow(label: "이름", last: course.file.components.isEmpty) { InlineField(isNew ? defaultTitle : "이름", text: $draft.title) }
                    if !course.file.components.isEmpty {
                        FormRow(label: "성적 항목", last: true) {
                            ChoiceMenu(selection: $draft.componentId,
                                       options: [(nil, "없음")] + course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) })
                        }
                    }
                }
            }
            Block("일시와 장소") {
                Card {
                    FormRow(label: "일시", detail: endsBeforeStart ? "끝나는 시간이 시작보다 빠릅니다" : nil) {
                        if draft.start == nil {
                            Button("정하기") { draft.start = workspace.calendar.date(byAdding: .hour, value: 33, to: workspace.calendar.startOfDay(for: .now)) }
                                .buttonStyle(.ghost)
                        } else {
                            DateChip(date: Binding(get: { draft.start ?? .now }, set: setStart))
                            Text("–").foregroundStyle(Theme.Palette.textTertiary)
                            if let end = endMinute {
                                TimeMenu(minute: Binding(get: { end }, set: setEnd))
                                Button { setEnd(nil) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help("끝나는 시간 지우기")
                            } else {
                                Button("끝 시간") { setEnd(min((startMinute ?? 9 * 60) + 120, 23 * 60 + 59)) }.buttonStyle(.ghost)
                            }
                        }
                    }
                    FormRow(label: "장소") { TextField("예: C104", text: $draft.location).pill(width: 140) }
                    FormRow(label: "허용 자료", last: true) { InlineField("예: 계산기, A4 한 장", text: $draft.allowed) }
                }
            }
            Block("범위") {
                Card {
                    FormRow(label: "단원") {
                        SearchMultiSelect(selection: $draft.scopeUnitIds, options: units.map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) },
                                          placeholder: units.isEmpty ? "단원 없음" : "고르기", subtree: { UnitTree.subtree(of: $0, in: course.file.units) })
                            .disabled(units.isEmpty)
                    }
                    FormRow(label: "설명", last: true) { InlineField("예: 3장까지, 증명 제외", text: $draft.scopeText) }
                }
            }
            FormTextArea(label: "메모", text: $draft.memo, height: 56)
        } onConfirm: {
            if draft.title.isEmpty { draft.title = defaultTitle }
            let d = draft
            let saved = isNew
                ? workspace.run(ExamAdd(id: d.id, course: course.id, title: d.title, kind: d.kind, start: d.start, end: d.end, location: d.location,
                                        component: d.componentId, scope: d.scopeUnitIds, scopeText: d.scopeText, allowed: d.allowed, memo: d.memo))
                : workspace.run(ExamSet(course: course.id, exam: d.id, title: .set(d.title), kind: .set(d.kind), start: .set(d.start), end: .set(d.end),
                                        location: .set(d.location), component: .set(d.componentId), scope: .set(d.scopeUnitIds),
                                        scopeText: .set(d.scopeText), allowed: .set(d.allowed), memo: .set(d.memo)))
            guard saved != nil else { return }
            dismiss()
        }
    }

    var startMinute: Int? {
        draft.start.map {
            let c = workspace.calendar.dateComponents([.hour, .minute], from: $0)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    var endMinute: Int? {
        draft.end.map {
            let c = workspace.calendar.dateComponents([.hour, .minute], from: $0)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    /// Moving the start carries the end along, so a date change keeps the exam's length.
    func setStart(_ new: Date) {
        if let old = draft.start, let end = draft.end { draft.end = end.addingTimeInterval(new.timeIntervalSince(old)) }
        draft.start = new
    }

    func setEnd(_ minute: Int?) {
        guard let start = draft.start else { return }
        draft.end = minute.flatMap { workspace.calendar.date(byAdding: .minute, value: $0, to: workspace.calendar.startOfDay(for: start)) }
    }
}

/// Today's plan items across the current semester's exams. Hidden when there are none.
struct ExamPlanTodayBlock: View {
    @Environment(Workspace.self) private var workspace
    let courses: [LoadedCourse]
    @State private var done: Set<UUID> = []

    var body: some View {
        let today = workspace.today
        let items = ExamPlan.items(on: today, courses: courses.map(\.file))
        if !items.isEmpty {
            Block("시험 계획", note: "\(items.filter { done.contains($0.item.id) }.count)/\(items.count) 완료") {
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { i, entry in
                        let accent = workspace.accent(entry.courseId)
                        CardRow(last: i == items.count - 1) {
                            CheckCircle(on: done.contains(entry.item.id)) { toggle(entry) }
                            .help(done.contains(entry.item.id) ? "완료 취소" : "완료")
                            .environment(\.accent, accent)
                            CourseDot(color: accent.color)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(entry.item.title).font(Theme.Typeface.bodyStrong).strikethrough(done.contains(entry.item.id))
                                Text("\(workspace.course(entry.courseId)?.title ?? "") · \(entry.exam.title)")
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                        .contextMenu { Button(done.contains(entry.item.id) ? "완료 취소" : "완료") { toggle(entry) } }
                    }
                }
            }
            .task(id: courses.map(\.id)) { done = workspace.donePlanItems(in: courses.map(\.id)) }
        }
    }

    func toggle(_ entry: ExamPlan.DayItem) {
        let new = !done.contains(entry.item.id)
        workspace.setPlanItem(entry.item.id, done: new, course: entry.courseId)
        if new { done.insert(entry.item.id) } else { done.remove(entry.item.id) }
    }
}

/// A unit's review in a dot: not started (hollow), behind, due, scheduled or settled.
private struct ReviewDot: View {
    let state: ReviewState?
    let today: LocalDate

    var body: some View {
        let (color, label): (Color?, String) = {
            guard let state else { return (nil, "아직 수업 전") }
            if state.settled && state.due == nil { return (Theme.Palette.success, "복습 끝") }
            guard let due = state.due else { return (Theme.Palette.textTertiary, "복습 중") }
            let late = due.days(until: today)
            let note = state.writeNoteFirst ? "복습 노트 없음 · " : ""
            return late > 0 ? (Theme.Palette.danger, "\(note)\(late)일 밀림") : late == 0 ? (Theme.Palette.warning, "\(note)오늘 복습") : (Theme.Palette.textTertiary, "다음 복습 \(due.shortLabel)")
        }()
        Group {
            if let color { Circle().fill(color) } else { Circle().strokeBorder(Theme.Palette.line, lineWidth: 1.5) }
        }
        .frame(width: 8, height: 8)
        .help(label)
        .accessibilityLabel(label)
    }
}
