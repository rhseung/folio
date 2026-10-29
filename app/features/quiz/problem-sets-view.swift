import FolioActions
import FolioDomain
import SwiftUI

/// Numbered problems solved on paper: a number grid per set, marked 맞음 / 틀림 / 해결 (docs/SPEC.md "문제 묶음").
struct ProblemSetsView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let model: QuizModel
    @State private var adding = false
    @State private var pendingDelete: ProblemSet?

    var body: some View {
        let sets = course.file.problemSets
        let units = course.outline.map(\.unit)
        let all = sets.flatMap { s in s.problems.map { (s.id, $0) } }
        let history = { (p: (UUID, ProblemSet.Problem)) in model.history(set: p.0, number: p.1.number) }
        let total = QuizStats.total(all, history: history)
        let byUnit = QuizStats.tally(all, keys: \.1.unitIds, history: history)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "문제 묶음", subtitle: sets.isEmpty ? "문제집, 증명집, 족보처럼 번호가 붙은 문제를 종이로 풀고 판정을 기록합니다"
                           : (["묶음 \(sets.count)개", "문제 \(total.items)개", "푼 문제 \(total.attempted)개"] + (total.open > 0 ? ["남은 오답 \(total.open)"] : [])).joined(separator: " · "))
                Spacer()
                Button("묶음 추가") { adding = true }.buttonStyle(.pointing(.borderedProminent))
            }
            ForEach(sets) { set in setBlock(set, units: units) }

            if sets.isEmpty {
                EmptyLine("묶음을 만들면 번호 격자가 생깁니다. 번호를 눌러 판정을 기록하고, 우클릭해 단원을 연결합니다.")
            } else {
                Block("단원별") {
                    let shown = units.filter { byUnit[$0.id] != nil }
                    Card {
                        if shown.isEmpty { CardRow(last: true) { EmptyLine("단원에 연결된 문제가 없습니다. 번호를 우클릭해 단원을 연결하세요") } }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                            TallyRow(title: unit.title, tally: byUnit[unit.id]!, unit: "문제", last: i == shown.count - 1)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { ProblemSetSheet(course: course) }
        .confirmationDialog("‘\(pendingDelete?.title ?? "")’ 묶음을 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("삭제", role: .destructive) {
                if let set = pendingDelete { workspace.run(ProblemSetRemove(course: course.id, set: set.id)) }
                pendingDelete = nil
            }
        } message: {
            Text("번호 격자와 단원 연결이 사라집니다. 문제지와 해설 파일, 풀이 기록은 그대로 둡니다.")
        }
    }

    func summary(_ t: WrongTally) -> String {
        (["\(t.items)문제", "맞음 \(t.correct)", "틀림 \(t.open)", "해결 \(t.resolved)"] + (t.items > t.attempted ? ["안 푼 \(t.items - t.attempted)"] : []))
            .joined(separator: " · ")
    }

    func material(_ id: UUID?) -> FolioDomain.Material? {
        id.flatMap { id in course.file.materials.first { $0.id == id } }
    }

    func setBlock(_ set: ProblemSet, units: [FolioDomain.Unit]) -> some View {
        let tally = QuizStats.total(set.problems) { model.history(set: set.id, number: $0.number) }
        return Block(title: set.title, note: summary(tally), trailing: {
            HStack(spacing: Theme.Space.m) {
                #if os(macOS)
                if let m = material(set.materialId) { Button("문제지") { open(m) }.buttonStyle(.ghost) }
                if let m = material(set.solutionMaterialId) { Button("해설") { open(m) }.buttonStyle(.ghost) }
                #endif
                Menu { setItems(set) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
            }
        }) {
            Card(padding: Theme.Space.m) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(set.problems, id: \.number) { problem in
                        ProblemCell(set: set, problem: problem, history: model.history(set: set.id, number: problem.number), units: units) { verdict in
                            workspace.run(ProblemRecord(course: course.id, attempt: ProblemAttemptEvent(problemSetId: set.id, number: problem.number, verdict: verdict)))
                            model.load(workspace, course)
                        } toggleUnit: { unit in
                            workspace.run(ProblemLinkUnit(course: course.id, set: set.id, number: problem.number, unit: unit,
                                                          linked: !problem.unitIds.contains(unit)))
                        }
                    }
                }
            }
        }
        .contextMenu { setItems(set) }
    }

    @ViewBuilder func setItems(_ set: ProblemSet) -> some View {
        #if os(macOS)
        if let m = material(set.materialId) { Button("문제지 열기") { open(m) } }
        if let m = material(set.solutionMaterialId) { Button("해설 열기") { open(m) } }
        if material(set.materialId) != nil || material(set.solutionMaterialId) != nil { Divider() }
        #endif
        Button("묶음 삭제…", role: .destructive) { pendingDelete = set }
    }

    #if os(macOS)
    func open(_ m: FolioDomain.Material) {
        NSWorkspace.shared.open(course.store.fileURL(m.path))
    }
    #endif
}

/// A new set: title, the problem and solution PDFs, the numbers, and the units every problem starts linked to.
struct ProblemSetSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State private var title = ""
    @State private var problemId: UUID?
    @State private var solutionId: UUID?
    @State private var numbers = ""
    @State private var unitIds: [UUID] = []

    var body: some View {
        let pdfs = course.file.materials.filter { !$0.isFolder && $0.status != .ignored && $0.path.lowercased().hasSuffix(".pdf") }.sorted { $0.path < $1.path }
        let parsed = ProblemSet.numbers(from: numbers)
        let pdfOptions = [PickOption(id: UUID?.none, title: "없음")]
            + pdfs.map { PickOption(id: Optional($0.id), title: ($0.path as NSString).lastPathComponent, detail: $0.path) }
        SheetForm(title: "문제 묶음 추가", confirm: "추가", disabled: title.trimmingCharacters(in: .whitespaces).isEmpty || parsed.isEmpty) {
            FormRow(label: "제목") { InlineField("예: 2024 중간 족보", text: $title) }
            FormRow(label: "문제지", detail: pdfs.isEmpty ? "자료 화면에서 파일 추적을 먼저 갱신하세요" : nil) {
                SearchSelect(selection: $problemId, options: pdfOptions)
            }
            FormRow(label: "해설") { SearchSelect(selection: $solutionId, options: pdfOptions) }
            FormRow(label: "문제 번호", detail: parsed.isEmpty ? "예: 1-10, 12, 13a" : "\(parsed.count)문제") {
                TextField("1-10", text: $numbers).pill(width: 160)
            }
            FormRow(label: "단원", detail: "모든 문제에 연결합니다. 문제마다 바꾸려면 번호를 우클릭하세요", last: true) {
                SearchMultiSelect(selection: $unitIds, options: course.unitOptions, placeholder: "없음")
            }
        } onConfirm: {
            var set = ProblemSet(device: workspace.device, at: .now, title: title.trimmingCharacters(in: .whitespaces),
                                 problems: parsed.map { ProblemSet.Problem(number: $0, unitIds: unitIds) })
            set.materialId = problemId
            set.solutionMaterialId = solutionId
            workspace.run(ProblemSetSave(course: course.id, set: set))
            dismiss()
        }
    }
}

/// One problem number. Its color is its place in the wrong flow; clicking records a verdict.
struct ProblemCell: View {
    @Environment(\.accent) private var accent
    let set: ProblemSet
    let problem: ProblemSet.Problem
    let history: AttemptHistory
    let units: [FolioDomain.Unit]
    let mark: (Verdict) -> Void
    let toggleUnit: (UUID) -> Void
    @State private var open = false

    var body: some View {
        let status = WrongFlow.status(history)
        let (fill, ink): (Color, Color) = switch status {
        case .open: (Theme.Palette.dangerFill, Theme.Palette.danger)
        case .resolved: (accent.tint, accent.ink)
        case .neverWrong: history.isEmpty ? (Theme.Palette.fill, Theme.Palette.textSecondary) : (Theme.Palette.success.opacity(Theme.Opacity.tint), Theme.Palette.success)
        }
        Button { open = true } label: {
            VStack(spacing: Theme.Space.xxs) {
                Text(problem.number).font(Theme.Typeface.bodyStrong).monospacedDigit()
                if case .resolved = status { Image(systemName: "checkmark").font(Theme.Glyph.tiny) }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(units.filter { problem.unitIds.contains($0.id) }.map(\.title).joined(separator: ", "))
        .contextMenu {
            Button(WrongFlow.isOpen(status) ? "해결" : "맞음") { mark(.correct) }
            Button("애매") { mark(.partial) }
            Button("틀림") { mark(.wrong) }
            Divider()
            Menu("단원") {
                ForEach(units) { u in
                    Button { toggleUnit(u.id) } label: {
                        if problem.unitIds.contains(u.id) { Label(u.title, systemImage: "checkmark") } else { Text(u.title) }
                    }
                }
            }
        }
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("\(set.title) · \(problem.number)번").font(Theme.Typeface.bodyStrong)
                HStack(spacing: Theme.Space.s) {
                    // A correct answer on an open problem is what resolves it; the button says so.
                    Button(WrongFlow.isOpen(status) ? "해결" : "맞음") { mark(.correct); open = false }
                    Button("애매") { mark(.partial); open = false }
                    Button("틀림") { mark(.wrong); open = false }
                }
                if !history.isEmpty {
                    Text(history.map { "\($0.day.short) \($0.verdict.label)" }.joined(separator: " · "))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Space.l)
        }
    }
}
