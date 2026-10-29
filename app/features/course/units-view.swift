import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitsView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    @State private var title = ""
    @State private var openUnit: UUID?
    @State private var pendingDelete: FolioDomain.Unit?
    @State private var quiz: [UUID: Workspace.UnitQuizStats] = [:]

    var body: some View {
        Group {
            if let id = openUnit, let unit = course.file.units.first(where: { $0.id == id }) {
                UnitDetail(course: course, unit: unit, quiz: quiz[id], delete: { pendingDelete = unit })
            } else {
                list
            }
        }
        .task(id: course.file.units.map(\.id)) { quiz = workspace.quizStats(of: course.id) }
        .confirmationDialog("‘\(pendingDelete?.title ?? "")’ 단원을 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("삭제", role: .destructive) {
                guard let unit = pendingDelete else { return }
                workspace.run(UnitRemove(course: course.id, unit: unit.id))
                if openUnit == unit.id { openUnit = nil }
                pendingDelete = nil
            }
        } message: {
            Text("회차와 시험 범위 연결이 풀리고, 하위 단원은 한 단계 위로 올라갑니다. 노트와 퀴즈 파일은 그대로 둡니다.")
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.unitStep, initial: true) { _, step in
            if step != nil { openUnit = UnitTree.outline(course.file.units).first?.unit.id }
        }
        #endif
    }

    /// A chapter (a top-level unit with units under it) heads its own block; top-level units without children
    /// share a plain card, so a flat outline still reads as one list.
    struct Chapter: Identifiable {
        var root: FolioDomain.Unit?
        var rows: [(unit: FolioDomain.Unit, depth: Int)] = []
        var id: UUID? { root?.id ?? rows.first?.unit.id }
    }

    static func groups(_ outline: [(unit: FolioDomain.Unit, depth: Int)]) -> [Chapter] {
        var groups: [Chapter] = []
        for (i, row) in outline.enumerated() {
            let hasChildren = i + 1 < outline.count && outline[i + 1].depth > row.depth
            if row.depth == 0 && hasChildren {
                groups.append(Chapter(root: row.unit))
            } else if row.depth == 0 {
                if groups.last.map({ $0.root == nil }) != true { groups.append(Chapter()) }
                groups[groups.count - 1].rows.append(row)
            } else {
                groups[groups.count - 1].rows.append((row.unit, row.depth - 1))
            }
        }
        return groups
    }

    var list: some View {
        let file = course.file
        let states = workspace.reviewStates(of: course.id, now: .now)
        let today = workspace.today
        let dueCount = states.values.filter { ($0.due.map { $0 <= today }) == true }.count
        let unlinked = file.sessions.filter { file.needsUnits($0, at: .now) }.sorted { $0.date > $1.date }
        return Page {
            PageHeader(title: "단원", subtitle: (["단원 \(file.units.count)개", "오늘 복습 \(dueCount)개"] + (file.units.isEmpty || unlinked.isEmpty ? [] : ["단원 없는 회차 \(unlinked.count)"])).joined(separator: " · "))
            if !file.units.isEmpty && !unlinked.isEmpty { unlinkedCard(unlinked) }
            ForEach(Self.groups(UnitTree.outline(file.units))) { group in
                if let root = group.root {
                    let exams = Set(file.exams.filter { $0.scopeUnitIds.contains(root.id) }.map(\.id))
                    Block(title: root.title, note: sessionsLine(root), trailing: {
                        HStack(spacing: Theme.Space.s) {
                            ForEach(file.exams.filter { exams.contains($0.id) }) { Chip($0.title) }
                            ReviewBadge(state: states[root.id], today: today)
                            Button { openUnit = root.id } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.ghost).tint(Theme.Palette.textTertiary)
                                .help("단원 열기")
                        }
                    }) {
                        Card { rows(group.rows, states: states, today: today, inheritedExams: exams) }
                    }
                    .contextMenu { menu(root) }
                } else {
                    Card { rows(group.rows, states: states, today: today, inheritedExams: []) }
                }
            }
            Card {
                CardRow(last: true) {
                    Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
                    TextField("새 단원 이름", text: $title).textFieldStyle(.plain).onSubmit(add)
                    Button("추가", action: add).buttonStyle(.pointing(.borderedProminent)).disabled(!workspace.can(UnitAdd(course: course.id, title: title)))
                }
            }
            if file.units.isEmpty {
                EmptyLine("단원은 복습과 퀴즈의 기준입니다. 교재의 장이나 강의계획서의 주제로 만들고, 단원을 열어 회차를 연결하세요.")
                    .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    /// Exam chips only where they differ from the chapter's, so a chapter all in the midterm says it once.
    func rows(_ rows: [(unit: FolioDomain.Unit, depth: Int)], states: [UUID: ReviewState], today: LocalDate, inheritedExams: Set<UUID>) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.unit.id) { i, row in
            let unit = row.unit
            let exams = course.file.exams.filter { $0.scopeUnitIds.contains(unit.id) }
            CardRow(last: i == rows.count - 1) {
                Button { openUnit = unit.id } label: {
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(unit.title).font(Theme.Typeface.body)
                            Text(detail(unit, state: states[unit.id])).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.m)
                        if Set(exams.map(\.id)) != inheritedExams { ForEach(exams) { Chip($0.title) } }
                        ReviewBadge(state: states[unit.id], today: today)
                    }
                    .padding(.leading, CGFloat(row.depth) * Theme.Space.xl)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
            }
            .contextMenu { menu(unit) }
        }
    }

    @ViewBuilder func menu(_ unit: FolioDomain.Unit) -> some View {
        Button("열기") { openUnit = unit.id }
        Button("위로") { move(unit, by: -1) }
        Button("아래로") { move(unit, by: 1) }
        Divider()
        Button("삭제…", role: .destructive) { pendingDelete = unit }
    }

    func sessionsLine(_ unit: FolioDomain.Unit) -> String {
        let names = course.file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }.map { course.file.name(of: $0) }
        return names.isEmpty ? "회차 없음" : names.count > 3 ? "\(names.prefix(3).joined(separator: ", ")) 외 \(names.count - 3)" : names.joined(separator: ", ")
    }

    /// Held classes no unit covers, newest first: linking one here starts its unit's review from that class.
    func unlinkedCard(_ sessions: [Session]) -> some View {
        let shown = sessions.prefix(6)
        return NoticeCard(title: "단원이 없는 지난 회차 \(sessions.count)개",
                          detail: "단원을 연결해야 그 수업이 단원 복습에 잡힙니다. 복습할 것이 없던 회차는 회차 메뉴에서 복습 필요 없음으로 두세요.",
                          systemImage: "link.badge.plus", trailing: { EmptyView() }) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && sessions.count <= shown.count) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(course.file.title(of: s)).lineLimit(1)
                        Text(s.date.formatted(.dateTime.month().day().weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.m)
                    SessionUnitsPicker(course: course, session: s)
                }
            }
            if sessions.count > shown.count {
                CardRow(last: true) { EmptyLine("외 \(sessions.count - shown.count)개") }
            }
        }
    }

    func detail(_ unit: FolioDomain.Unit, state: ReviewState?) -> String {
        var parts = [sessionsLine(unit)]
        if let state, !state.settled { parts.append("간격 \(workspace.settings.review.interval(atStep: state.step))일") }
        if let q = quiz[unit.id] {
            parts.append("퀴즈 \(q.cards)장")
            if q.openWrong > 0 { parts.append("오답 \(q.openWrong)") }
        }
        return parts.joined(separator: " · ")
    }

    func move(_ unit: FolioDomain.Unit, by offset: Int) {
        workspace.run(UnitMove(course: course.id, unit: unit.id, target: .by(offset)))
    }

    func add() {
        guard workspace.run(UnitAdd(course: course.id, title: title)) != nil else { return }
        title = ""
    }
}

struct ReviewBadge: View {
    let state: ReviewState?
    let today: LocalDate

    var body: some View {
        if let state {
            if state.settled && state.due == nil {
                Chip("복습 끝", tone: .success)
            } else if let due = state.due {
                let late = due.days(until: today)
                if state.writeNoteFirst && late >= 0 {
                    Chip(late > 0 ? "복습 노트 · \(late)일 밀림" : "복습 노트 작성", tone: .warning)
                } else if late > 0 {
                    Chip("\(late)일 밀림", tone: .danger)
                } else if late == 0 {
                    Chip("오늘", tone: .accent)
                } else {
                    Chip(due.shortLabel)
                }
            }
        } else {
            Chip("시작 전")
        }
    }
}

extension LocalDate {
    var shortLabel: String {
        date(in: .current)?.formatted(.dateTime.month().day().weekday()) ?? description
    }
}

/// Renaming, moving and deleting the unit come last, since they are rare.
struct UnitDetail: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.searchTarget) private var searchTarget
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    let quiz: Workspace.UnitQuizStats?
    let delete: () -> Void
    @State private var name = ""
    @State private var notes: [NoteFile] = []
    @State private var reviewing = false

    var body: some View {
        let file = course.file
        let now = Date.now
        let today = workspace.settings.studyDay(of: now, calendar: workspace.calendar)
        let state = workspace.reviewStates(of: course.id, now: now)[unit.id]
        let sessions = file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
        let history = workspace.reviews(of: course.id).filter { $0.event.unitId == unit.id }.reversed()
        let intervals = workspace.settings.review.intervals
        // Rough and review notes already sit in their class's row above.
        let classNotes = Set(sessions.flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        let otherNotes = notes.filter { $0.meta.id.map(classNotes.contains) != true }
        let materials = materials(sessions: sessions)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: unit.title, subtitle: parentPath) { ReviewBadge(state: state, today: today) }
                Spacer()
                Button { reviewing = true } label: { Label("복습 시작", systemImage: "play.fill") }
                    .buttonStyle(.pointing(.borderedProminent))
                    .controlSize(.large)
            }

            StatStrip(items: [
                .init(title: "다음 복습", value: state?.due.map { $0 < today ? "\($0.days(until: today))일 밀림" : $0 == today ? "오늘" : $0.shortLabel } ?? (state?.settled == true ? "복습 끝" : "-"),
                      tone: (state?.due.map { $0 < today }) == true ? .danger : .plain),
                .init(title: "간격", value: state.map { "\(workspace.settings.review.interval(atStep: $0.step))일" } ?? "-",
                      detail: state.map { "\($0.step + 1)/\(intervals.count)단계" }),
                .init(title: "복습", value: "\(history.count)회"),
                .init(title: "퀴즈", value: quiz.map { "\($0.cards)장" } ?? "-", detail: quiz.flatMap { $0.openWrong > 0 ? "오답 \($0.openWrong)" : nil },
                      tone: (quiz?.openWrong ?? 0) > 0 ? .warning : .plain),
            ])

            Block(title: "강의 회차", note: sessions.isEmpty ? nil : "\(sessions.count)회") {
                ToggleMenu(title: "회차 연결", items: file.sessions.sorted { $0.date < $1.date }.map {
                    (id: $0.id, label: file.title(of: $0), on: unit.sessionIds.contains($0.id))
                }) { id in workspace.run(UnitLink(course: course.id, unit: unit.id, sessions: [id], linked: !unit.sessionIds.contains(id))) }
            } content: {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine("연결된 회차가 없습니다. 회차를 연결하면 그 날부터 복습 주기가 시작됩니다.") } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) { sessionRow(s, now: now) }
                            .contentShape(.rect)
                            .contextMenu { sessionMenu(s, now: now) }
                    }
                }
            }

            Block("노트", note: "단원 정리와 이 단원을 단 노트") {
                Card {
                    if otherNotes.isEmpty {
                        CardRow(last: true) { EmptyLine("노트 편집 화면의 연결 메뉴에서 단원 정리로 이 단원을 고르면 여기 모입니다") }
                    }
                    ForEach(Array(otherNotes.enumerated()), id: \.element.url) { i, note in
                        CardRow(last: i == otherNotes.count - 1) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.Palette.textTertiary)
                            Text(note.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.m)
                            Chip(note.meta.kind.label, tone: note.meta.kind == .topic ? .accent : .plain)
                        }
                        .opens(note.meta.id.map { id in { openNote(id) } })
                        .contextMenu { if let id = note.meta.id { Button("열기") { openNote(id) } } }
                    }
                }
            }

            Block("자료", note: "이 단원이나 그 회차에 연결한 파일") {
                Card {
                    if materials.isEmpty {
                        CardRow(last: true) { EmptyLine("자료 화면에서 파일의 연결로 이 단원이나 회차를 고르면 여기 모입니다") }
                    }
                    ForEach(Array(materials.enumerated()), id: \.element.material.id) { i, item in
                        let m = item.material
                        let missing = m.status == .missing
                        CardRow(last: i == materials.count - 1) {
                            Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
                                .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text((m.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).help(m.path)
                                Text(item.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.m)
                            if missing { Chip("파일 없음", tone: .danger) }
                        }
                        .opens(missing ? nil : { openMaterial(m) })
                        .contextMenu {
                            if !missing { Button("열기") { openMaterial(m) } }
                            #if os(macOS)
                            if !missing { Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([course.store.fileURL(m.path)]) } }
                            #endif
                        }
                    }
                }
            }

            Block("시험 범위") {
                Card(padding: Theme.Space.m) {
                    if file.exams.isEmpty {
                        EmptyLine("시험이 없습니다. 시험 화면에서 추가하세요.").padding(.horizontal, Theme.Space.xs)
                    } else {
                        // Wraps: a course with weekly quizzes has more exams than one line holds.
                        FlowLayout(spacing: Theme.Space.s) {
                            ForEach(file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }) { exam in
                                let on = exam.scopeUnitIds.contains(unit.id)
                                Button { workspace.run(ExamScope(course: course.id, exam: exam.id, unit: unit.id, included: !on)) } label: {
                                    Label(exam.title.isEmpty ? exam.kind.label : exam.title, systemImage: on ? "checkmark" : "plus")
                                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                                        .padding(Theme.Inset.toggle)
                                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                                        .contentShape(.capsule)
                                }
                                .buttonStyle(.pointing(.plain))
                            }
                        }
                    }
                }
            }

            Block("복습 기록", note: history.isEmpty ? nil : "최근 순") {
                Card {
                    if history.isEmpty { CardRow(last: true) { EmptyLine("아직 복습하지 않았습니다") } }
                    ForEach(Array(history.enumerated()), id: \.offset) { i, entry in
                        CardRow(last: i == history.count - 1) {
                            Text(workspace.settings.studyDay(of: entry.at, calendar: workspace.calendar).shortLabel).monospacedDigit()
                            Spacer()
                            Text(minutes(entry.event.seconds)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            Chip(entry.event.result.label, tone: entry.event.result == .again ? .danger : entry.event.result == .hard ? .warning : .plain)
                        }
                    }
                }
            }

            Block(title: "단원 편집", note: nil, trailing: {
                Button("단원 삭제…", role: .destructive, action: delete).buttonStyle(.ghost).tint(Theme.Palette.danger)
            }) {
                Card {
                    FormRow(label: "이름") {
                        InlineField("단원 이름", text: $name).onSubmit(rename)
                    }
                    FormRow(label: "상위 단원") {
                        SearchSelect(selection: Binding(get: { unit.parentId }, set: setParent),
                                     options: [PickOption(id: UUID?.none, title: "없음")] + UnitTree.parentChoices(for: unit.id, in: file.units).map { PickOption(id: Optional($0.id), title: $0.title) })
                    }
                    FormRow(label: "순서", detail: "같은 상위 단원 안에서", last: true) {
                        HStack(spacing: Theme.Space.s) {
                            Button { move(-1) } label: { Image(systemName: "arrow.up") }.help("위로")
                            Button { move(1) } label: { Image(systemName: "arrow.down") }.help("아래로")
                        }
                    }
                }
            }
        }
        .task(id: unit.id) {
            name = unit.title
            notes = workspace.notes(for: unit, in: course.id)
        }
        .onChange(of: unit.sessionIds) { notes = workspace.notes(for: unit, in: course.id) }
        .onChange(of: workspace.notesRevision) { notes = workspace.notes(for: unit, in: course.id) }
        .onDisappear(perform: rename)
        .crumb(unit.title, level: 2, symbol: "list.bullet.indent")
        .sheet(isPresented: $reviewing) { ReviewView(courseId: course.id, unitId: unit.id) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.unitStep, initial: true) { _, step in reviewing = step == "review" }
        #endif
    }

    /// Date, name and topic, then the rough and review notes in the sessions page's fixed slots, so both pages read alike.
    @ViewBuilder func sessionRow(_ s: Session, now: Date) -> some View {
        let file = course.file
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(s.date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
            Text(s.date.formatted(.dateTime.weekday())).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(width: 84, alignment: .leading)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(file.name(of: s)).font(Theme.Typeface.bodyStrong).strikethrough(s.isCancelled)
            if !s.topic.isEmpty {
                Text(s.topic).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        SessionNoteSlots(file: file, session: s, openNote: openNote) { if $0 == .review { openReview(s) } }
        Button { unlink(s) } label: { Image(systemName: "xmark") }
            .buttonStyle(.ghost)
            .foregroundStyle(Theme.Palette.textTertiary)
            .help("연결 해제")
    }

    @ViewBuilder func sessionMenu(_ s: Session, now: Date) -> some View {
        if let id = s.roughNoteId { Button("러프 노트 열기") { openNote(id) } }
        if s.reviewNoteId != nil || course.file.needsReviewNote(s, at: now) {
            Button(s.reviewNoteId == nil ? "복습 노트 만들기" : "복습 노트 열기") { openReview(s) }
        }
        Divider()
        Button("이 단원에서 연결 해제") { unlink(s) }
    }

    func openReview(_ s: Session) {
        if let id = workspace.note(.review, of: s.id, in: course.id) { openNote(id) }
    }

    func unlink(_ s: Session) {
        workspace.run(UnitLink(course: course.id, unit: unit.id, sessions: [s.id], linked: false))
    }

    func openMaterial(_ m: FolioDomain.Material) {
        searchTarget.wrappedValue = SearchTarget(courseId: course.id, section: .materials, materialId: m.id)
    }

    /// Through the search target, which the course screen already follows to a note or a file.
    func openNote(_ id: UUID) {
        searchTarget.wrappedValue = SearchTarget(courseId: course.id, section: .notes, noteId: id)
    }

    /// Files linked to the unit itself or to one of its classes, by role as on the materials page.
    func materials(sessions: [Session]) -> [(material: FolioDomain.Material, detail: String)] {
        let file = course.file
        let ids = Set(sessions.map(\.id))
        let roles = MaterialRole.allCases
        return file.materials
            .filter { $0.status != .ignored }
            .compactMap { m -> (material: FolioDomain.Material, detail: String)? in
                let links = file.sessionLinks(of: m.id).filter { ids.contains($0.session.id) }
                guard m.unitIds.contains(unit.id) || !links.isEmpty else { return nil }
                let role = m.status == .unclassified ? "미분류" : (m.role ?? .other).label
                return (m, ([role] + links.map { file.name(of: $0.session) + $0.link.pageLabel }).joined(separator: " · "))
            }
            .sorted { a, b in
                let (x, y) = (roles.firstIndex { $0 == a.material.role } ?? roles.count, roles.firstIndex { $0 == b.material.role } ?? roles.count)
                return x != y ? x < y : a.material.path.localizedStandardCompare(b.material.path) == .orderedAscending
            }
    }

    var parentPath: String? {
        var titles: [String] = []
        var next = unit.parentId
        while let id = next, let parent = course.file.units.first(where: { $0.id == id }), titles.count < 8 {
            titles.insert(parent.title, at: 0)
            next = parent.parentId
        }
        return titles.isEmpty ? nil : titles.joined(separator: " › ")
    }

    func rename() {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != unit.title else { return }
        workspace.run(UnitSet(course: course.id, unit: unit.id, title: new))
    }

    func setParent(_ parent: UUID?) {
        workspace.run(UnitMove(course: course.id, unit: unit.id, target: .parent(parent)))
    }

    func move(_ offset: Int) {
        workspace.run(UnitMove(course: course.id, unit: unit.id, target: .by(offset)))
    }

    func minutes(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)초" : "\(seconds / 60)분"
    }
}

struct ToggleMenu: View {
    let title: String
    let items: [(id: UUID, label: String, on: Bool)]
    let toggle: (UUID) -> Void

    var body: some View {
        SearchPicker(options: items.map { PickOption(id: $0.id, title: $0.label) }, isSelected: { id in items.contains { $0.id == id && $0.on } },
                     pick: toggle, multiple: true) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "link")
                Text(title)
            }
            .font(Theme.Typeface.caption)
            .padding(.horizontal, Theme.Space.s + 2)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Palette.fill, in: .capsule)
            .contentShape(.capsule)
        }
    }
}

extension ReviewResult {
    var label: String {
        switch self {
        case .again: "다시"
        case .hard: "어려움"
        case .good: "보통"
        case .easy: "쉬움"
        case .skip: "건너뜀"
        }
    }
}
