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
                Button(.problemSetAdd, systemImage: "plus") { sheets.present(.problemSet(course: course.id)) }.buttonStyle(.secondary)
                Button(.unitsSolve, systemImage: "pencil.and.list.clipboard") { sheets.present(.solve(model.solveRequest())) }
                    .buttonStyle(.prominent).disabled(model.isEmpty)
            }
            ForEach(model.extractions) { e in
                ExtractionNotice(extraction: e, model: model) { sheets.present(.problemDraft(course: course.id, material: e.material)) }
            }
            if model.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .problemsEmpty)) } }
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
