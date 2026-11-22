import FolioDomain
import SwiftUI

struct ProblemsView: View {
    @State private var model: ProblemsModel
    @Environment(\.itemSheets) private var sheets
    @Environment(\.openLink) private var openLink
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
                Button(.unitsSolve, systemImage: "pencil.and.list.clipboard") { openLink.solve(model.solveRequest()) }
                    .buttonStyle(.prominent).disabled(model.isEmpty)
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
                        Button(.unitsSolve) { openLink.solve(model.solveRequest(group)) }.buttonStyle(.ghost)
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
                                            openLink.solve(model.solveRequest(r))
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
