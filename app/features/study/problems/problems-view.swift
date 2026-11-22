import FolioDomain
import SwiftUI

struct ProblemsView: View {
    @State private var model: ProblemsModel
    @Environment(\.itemSheets) private var sheets
    let course: LoadedCourse

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: ProblemsModel(workspace: workspace, courseId: course.id))
        self.course = course
    }

    var body: some View {
        let groups = model.groups
        Page {
            FoldingRow(labelRoom: Theme.Size.pageHeaderRoom) {
                PageHeader(title: String(localized: .problemsTitle), subtitle: model.subtitle)
            } control: {
                // 접힌 줄에도 세 단추가 다 들어가지 않으면 뽑기 단추만 아이콘으로 줄인다. 다른 두 단추가 잘리지 않게 하려는 것이다.
                ViewThatFits(in: .horizontal) {
                    headerActions(compact: false)
                    headerActions(compact: true)
                }
            }
            ForEach(model.extractions) { e in
                ExtractionNotice(extraction: e, model: model) { sheets.present(.problemDraft(course: course.id, material: e.material)) }
            }
            if model.isEmpty {
                Card {
                    CardRow(last: true) {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            EmptyLine(String(localized: .problemsEmpty))
                            ExtractPick(model: model)
                        }
                    }
                }
            } else {
                FoldingRow {
                    SegmentedControl(selection: $model.filter, options: model.filterOptions)
                } control: {
                    Combobox(selection: $model.unit, options: model.unitOptions)
                }
                if groups.isEmpty { EmptyLine(String(localized: .problemsNoMatch)).padding(.horizontal, Theme.Space.m) }
                ForEach(groups) { group in
                    Block(
                        title: group.set.title, note: group.note
                    ) {
                        Button(.unitsSolve) { sheets.present(.solve(model.solveRequest(group))) }.buttonStyle(.ghost)
                            .disabled(group.records.isEmpty)
                        PageMenuButton { ProblemSetMenu(courseId: course.id, set: group.set) }
                    } content: {
                        Card(padding: Theme.Space.m) {
                            if group.records.isEmpty {
                                EmptyLine(String(localized: .problemsSetEmpty))
                            } else {
                                FlowLayout(spacing: Theme.Space.s) {
                                    ForEach(group.records, id: \.problem.id) { r in
                                        ProblemCell(number: r.problem.number, tone: model.tone(r), help: model.help(r)) {
                                            sheets.present(.solve(model.solveRequest(r)))
                                        }
                                        .contextMenu { ProblemMenu(courseId: course.id, set: group.set, problem: r.problem) }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .linkTarget(group.set.id)
                }
            }
        }
    }

    private func headerActions(compact: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            ExtractPick(model: model, compact: compact)
            Button(.problemSetAdd, systemImage: "plus") { sheets.present(.problemSet(course: course.id)) }.buttonStyle(.secondary)
            Button(.unitsSolve, systemImage: "pencil.and.list.clipboard") { sheets.present(.solve(model.solveRequest())) }
                .buttonStyle(.prominent).disabled(model.isEmpty)
        }
    }
}

// 과목의 문제지 하나를 골라 뽑는다. 목록이 길어질 수 있어 찾기 칸이 있는 목록으로 연다.
private struct ExtractPick: View {
    let model: ProblemsModel
    var compact = false
    @State private var open = false

    var body: some View {
        let options = model.sheetOptions
        if !options.isEmpty {
            CommandList(options: options, onSelect: model.extract, prompt: String(localized: .problemExtractPickPrompt), isPresented: $open)
            {
                let button = Button(.problemExtractPick, systemImage: "sparkles") { open = true }.buttonStyle(.secondary)
                if compact { button.labelStyle(.iconOnly) } else { button }
            }
        }
    }
}

private struct ExtractionNotice: View {
    let extraction: ProblemsModel.Extraction
    let model: ProblemsModel
    let review: () -> Void

    var body: some View {
        switch extraction.phase {
        case .working:
            NoticeCard(title: extraction.title, systemImage: "sparkles", tone: .info) { ProgressView().controlSize(.small) }
        case .failed:
            NoticeCard(title: extraction.title, detail: extraction.detail, systemImage: "exclamationmark.triangle.fill") {
                HStack(spacing: Theme.Space.s) {
                    Button(.commonClose) { model.dismiss(extraction) }.buttonStyle(.ghost)
                    Button(.problemExtractRetry) { model.retry(extraction) }.buttonStyle(.secondary)
                }
            }
        case .ready:
            NoticeCard(title: extraction.title, systemImage: "sparkles") {
                HStack(spacing: Theme.Space.s) {
                    Button(.problemExtractReview, action: review).buttonStyle(.secondary)
                    Button(.problemExtractAcceptAll) { model.acceptAll(extraction) }.buttonStyle(.prominent)
                }
            } rows: {
                if let detail = extraction.detail {
                    CardRow(last: true) { Text(detail).foregroundStyle(Theme.Palette.textSecondary) }
                }
            }
        }
    }
}
