import FolioActions
import FolioDomain
import SwiftUI

struct ScoreEntrySheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    let entry: ScoreEntry
    @State private var componentId: UUID
    @State private var title: String
    @State private var score: String
    @State private var max: String
    @State private var mean: String
    @State private var stdDev: String
    @State private var excused: Bool
    @State private var confirmingDelete = false

    init(course: LoadedCourse, entry: ScoreEntry) {
        self.course = course
        self.entry = entry
        _componentId = State(initialValue: entry.componentId)
        _title = State(initialValue: entry.title)
        let isNew = !course.file.scores.contains { $0.id == entry.id }
        _score = State(initialValue: isNew ? "" : entry.score.formatted(.number.grouping(.never)))
        _max = State(initialValue: entry.max.formatted(.number.grouping(.never)))
        _mean = State(initialValue: entry.mean?.formatted(.number.grouping(.never)) ?? "")
        _stdDev = State(initialValue: entry.stdDev?.formatted(.number.grouping(.never)) ?? "")
        _excused = State(initialValue: entry.excused)
    }

    var body: some View {
        let s = Double(score), m = Double(max)
        let z = s.flatMap { s in Double(mean).flatMap { mu in Double(stdDev).flatMap { $0 > 0 ? (s - mu) / $0 : nil } } }
        let valid = s != nil && (m ?? 0) > 0 && (mean.isEmpty || Double(mean) != nil) && (stdDev.isEmpty || Double(stdDev) != nil)
        let isNew = !course.file.scores.contains { $0.id == entry.id }
        let single = course.file.components.first { $0.id == componentId }?.aggregation == .single
        SheetForm(title: isNew ? "점수 추가" : "점수 편집", confirm: isNew ? "추가" : "저장", disabled: !valid,
                  deleteTitle: isNew ? nil : "점수 삭제", onDelete: { confirmingDelete = true }) {
            // A new score is added from its component's tile, which already picked the component.
            if !isNew {
                FormRow(label: "평가 항목") {
                    ChoiceMenu(selection: $componentId, options: course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) })
                }
            }
            if !single { FormRow(label: "제목") { InlineField("예: Quiz 3", text: $title) } }
            FormRow(label: "점수") {
                HStack(spacing: Theme.Space.s) {
                    TextField("점수", text: $score).pill(width: 72)
                    Text("/").foregroundStyle(Theme.Palette.textTertiary)
                    TextField("만점", text: $max).pill(width: 72)
                }
            }
            let gap = s.flatMap { s in Double(mean).map { s - $0 } }
            FormRow(label: "평균과 표준편차", detail: z.map(\.sigmas) ?? gap.map { "\($0.points) · 표준편차는 없으면 비워 둡니다" } ?? "공개되면 넣어 평균에서 얼마나 떨어졌는지 봅니다") {
                HStack(spacing: Theme.Space.s) {
                    TextField("평균", text: $mean).pill(width: 72)
                    Text("±").foregroundStyle(Theme.Palette.textTertiary)
                    TextField("표준편차", text: $stdDev).pill(width: 72)
                }
            }
            FormRow(label: "반영", detail: "면제하면 계산에서 뺍니다", last: true) {
                ChoiceMenu(selection: $excused, options: [(false, "반영"), (true, "면제")])
            }
        } onConfirm: {
            guard let s, let m else { return }
            let saved = course.file.scores.contains { $0.id == entry.id }
                ? workspace.run(ScoreSet(course: course.id, score: entry.id, component: .set(componentId), title: .set(title), value: .set(s), max: .set(m),
                                         mean: .set(Double(mean)), stdDev: .set(Double(stdDev)), excused: .set(excused)))
                : workspace.run(ScoreAdd(id: entry.id, course: course.id, component: componentId, title: title, score: s, max: m,
                                         mean: Double(mean), stdDev: Double(stdDev), date: entry.date, exam: entry.examId, assignment: entry.assignmentId,
                                         excused: excused))
            guard saved != nil else { return }
            dismiss()
        }
        .confirmationDialog(Self.deleteTitle(entry), isPresented: $confirmingDelete) {
            Button("삭제", role: .destructive) {
                Self.delete(entry, in: course, workspace: workspace)
                dismiss()
            }
        }
    }

    static func deleteTitle(_ entry: ScoreEntry) -> String {
        entry.title.isEmpty ? "이 점수를 삭제할까요?" : "‘\(entry.title)’ 점수를 삭제할까요?"
    }

    static func delete(_ entry: ScoreEntry, in course: LoadedCourse, workspace: Workspace) {
        workspace.run(ScoreRemove(course: course.id, score: entry.id))
    }
}

struct ComponentSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    let component: GradeComponent
    @State private var name: String
    @State private var group: String
    @State private var weight: Double
    @State private var aggregation: Aggregation
    @State private var expectedCount: Int?
    @State private var confirmingDelete = false

    init(course: LoadedCourse, component: GradeComponent) {
        self.course = course
        self.component = component
        _name = State(initialValue: component.name)
        _group = State(initialValue: component.group ?? "")
        _weight = State(initialValue: component.weight)
        _aggregation = State(initialValue: component.aggregation)
        _expectedCount = State(initialValue: component.expectedCount)
    }

    var isNew: Bool { !course.file.components.contains { $0.id == component.id } }

    var count: Int? {
        switch aggregation {
        case .dropLowest(let n), .bestOf(let n): n
        default: nil
        }
    }

    var body: some View {
        let n = count ?? 1
        SheetForm(title: isNew ? "평가 항목 추가" : "평가 항목 편집", confirm: isNew ? "추가" : "저장",
                  disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || weight < 0 || (expectedCount ?? 1) < 1,
                  deleteTitle: isNew ? nil : "항목 삭제", onDelete: { confirmingDelete = true }) {
            FormRow(label: "이름") { InlineField("예: Quiz", text: $name) }
            FormRow(label: "묶음", detail: "강의계획서가 한 제목 아래 묶은 항목. 과제 하나가 묶음 전체에 점수를 냅니다") {
                InlineField("예: Reports", text: $group)
            }
            FormRow(label: "비중") {
                HStack(spacing: Theme.Space.s) {
                    TextField("비중", value: $weight, format: .number).pill(width: 72)
                    Text("%").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            FormRow(label: "반영 규칙", last: aggregation == .single) {
                ChoiceMenu(selection: $aggregation, options: [
                    (.sum, "합산"), (.mean, "평균"), (.single, "단일"), (.dropLowest(n), "최저 점수 제외"), (.bestOf(n), "상위 점수만"),
                ])
            }
            if count != nil {
                FormRow(label: aggregation == .dropLowest(n) ? "제외할 횟수" : "반영할 횟수") {
                    ChoiceMenu(selection: Binding(
                        get: { n },
                        set: { aggregation = aggregation == .dropLowest(n) ? .dropLowest($0) : .bestOf($0) }
                    ), options: (1...10).map { ($0, "\($0)회") })
                }
            }
            // A single score is one by definition, so a count there would only contradict it.
            if aggregation != .single {
                FormRow(label: "예정 횟수", detail: "정하지 않으면 확보 점수에 넣지 않고 예상 점수에만 씁니다", last: true) {
                    HStack(spacing: Theme.Space.tight) {
                        TextField("정하지 않음", value: $expectedCount, format: .number).pill(width: 110)
                        Text("회").foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        } onConfirm: {
            let saved = isNew
                ? workspace.run(ComponentAdd(id: component.id, course: course.id, name: name, weight: weight, aggregation: aggregation,
                                             expectedCount: expectedCount, group: group))
                : workspace.run(ComponentSet(course: course.id, component: component.id, name: .set(name), weight: .set(weight),
                                             aggregation: .set(aggregation), expectedCount: .set(expectedCount), group: .set(group)))
            guard saved != nil else { return }
            dismiss()
        }
        .confirmationDialog(Self.deleteTitle(component), isPresented: $confirmingDelete) {
            Button("삭제", role: .destructive) {
                Self.delete(component, in: course, workspace: workspace)
                dismiss()
            }
        } message: {
            Self.deleteMessage(component, in: course)
        }
    }

    static func deleteTitle(_ component: GradeComponent) -> String { "‘\(component.name)’ 항목을 삭제할까요?" }

    @ViewBuilder static func deleteMessage(_ component: GradeComponent, in course: LoadedCourse) -> some View {
        let scores = course.file.scores.filter { $0.componentId == component.id }.count
        if scores > 0 { Text("이 항목의 점수 \(scores)개도 함께 삭제됩니다.") }
    }

    /// Its scores go with it; assignments and exams that fed it stay, unlinked.
    static func delete(_ component: GradeComponent, in course: LoadedCourse, workspace: Workspace) {
        workspace.run(ComponentRemove(course: course.id, component: component.id))
    }
}

struct PolicySheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State private var caps: [AttendanceCap]
    @State private var ratio: String
    @State private var late: String
    @State private var notes: String
    @State private var topShare: String
    @State private var lates: String

    init(course: LoadedCourse) {
        self.course = course
        let p = course.file.policy
        _caps = State(initialValue: p.attendanceCap.sorted { $0.absences < $1.absences })
        _ratio = State(initialValue: p.minAttendanceRatio.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) } ?? "")
        _late = State(initialValue: p.latePolicy ?? "")
        _notes = State(initialValue: p.notes)
        _topShare = State(initialValue: p.topGradeRatio.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) } ?? "")
        _lates = State(initialValue: p.latesPerAbsence.map(String.init) ?? "")
    }

    var body: some View {
        let grades = workspace.catalog.letterGrades.filter { $0.points != nil }.sorted { $0.points! > $1.points! }
        let badShare = !topShare.isEmpty && !(Double(topShare).map { $0 > 0 && $0 < 100 } ?? false)
        let badLates = !lates.isEmpty && !(Int(lates).map { $0 > 0 } ?? false)
        let badRatio = !ratio.isEmpty && !(Double(ratio).map { $0 > 0 && $0 <= 100 } ?? false)
        SheetForm(title: "성적 규칙", confirm: "저장", disabled: badRatio || badShare || badLates, carded: false, width: 560) {
            if course.file.course.gradingMode == .relative {
                Block("상대평가") {
                    Card {
                        FormRow(label: "A 비율", detail: "나머지는 B와 C. 비우면 \(Int(GradePolicy.defaultTopGradeRatio * 100))%", last: true) {
                            HStack(spacing: Theme.Space.s) {
                                TextField("\(Int(GradePolicy.defaultTopGradeRatio * 100))", text: $topShare).pill(width: 72)
                                Text("%").foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            Block(title: "결석 상한", note: "그 횟수부터 받을 수 있는 최대 성적", trailing: {
                Button { addCap(grades) } label: { Label("상한 추가", systemImage: "plus") }
                    .buttonStyle(.ghost).disabled(grades.isEmpty)
            }) {
                Card {
                    if caps.isEmpty { CardRow(last: true) { EmptyLine("결석 상한이 없습니다") } }
                    ForEach(caps.indices, id: \.self) { i in
                        CardRow(last: i == caps.count - 1) {
                            Text("결석")
                            TextField("횟수", value: cap(i).absences, format: .number).pill(width: 56)
                            Text("회부터 최대").foregroundStyle(Theme.Palette.textSecondary)
                            ChoiceMenu(selection: cap(i).maxGrade, options: grades.map { ($0.id, $0.symbol) })
                            Spacer()
                            Button { caps.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.ghost)
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .help("상한 지우기")
                        }
                    }
                }
            }
            Block("그 밖의 규칙") {
                Card {
                    FormRow(label: "지각", detail: "비우면 지각은 결석으로 세지 않습니다") {
                        HStack(spacing: Theme.Space.s) {
                            TextField("없음", text: $lates).pill(width: 56)
                            Text("회 = 결석 1회").foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    FormRow(label: "최소 출석 비율") {
                        HStack(spacing: Theme.Space.s) {
                            TextField("없음", text: $ratio).pill(width: 72)
                            Text("%").foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    FormRow(label: "지각 제출", last: true) { InlineField("예: 하루 10% 감점", text: $late) }
                }
            }
            FormTextArea(label: "구조화하지 못한 규칙", detail: "위 항목과 성적 구성으로 나타낼 수 없는 것만 남깁니다", text: $notes, height: 96)
        } onConfirm: {
            var policy = course.file.policy
            policy.attendanceCap = caps
            policy.minAttendanceRatio = Double(ratio).map { $0 / 100 }
            policy.latePolicy = late.isEmpty ? nil : late
            policy.notes = notes
            policy.topGradeRatio = Double(topShare).map { $0 / 100 }
            policy.latesPerAbsence = Int(lates)
            guard workspace.run(PolicySet(course: course.id, policy: policy)) != nil else { return }
            dismiss()
        }
    }

    func addCap(_ grades: [LetterGrade]) {
        guard let lowest = grades.last else { return }
        caps.append(AttendanceCap(absences: (caps.map(\.absences).max() ?? 5) + 1, maxGrade: lowest.id))
    }

    /// Guards the index: a row's field can still write for a moment after its cap was removed.
    func cap(_ i: Int) -> Binding<AttendanceCap> {
        Binding(
            get: { caps.indices.contains(i) ? caps[i] : AttendanceCap(absences: 0, maxGrade: UUID()) },
            set: { if caps.indices.contains(i) { caps[i] = $0 } }
        )
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let added = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if added > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], current.y + current.height + spacing, size.width, size.height)
            } else {
                current = (current.items + [i], current.y, added, Swift.max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

extension Double {
    /// A z score the way grades are talked about: `평균 +2.5σ`, `평균 -0.7σ`, or `평균` when it rounds to zero.
    var sigmas: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? "평균" : "평균 \(String(format: "%+.1f", r))σ"
    }

    /// A gap from the class mean in points, for a score whose standard deviation wasn't published: `평균 +8점`.
    var points: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? "평균" : "평균 \(r > 0 ? "+" : "")\(r.formatted())점"
    }

    var percent: String { (self * 100).formatted(.number.precision(.fractionLength(0...1))) + "%" }
}
