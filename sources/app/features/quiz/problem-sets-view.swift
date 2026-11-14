import FolioDomain
import SwiftUI

struct ProblemSetsView: View {
    let course: LoadedCourse
    @Bindable var model: QuizModel
    @State private var adding = false
    @Environment(\.openLink) private var openLink

    var body: some View {
        let sets = course.file.problemSets
        let units = course.outline.map(\.unit)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .quizProblemsTitle), subtitle: model.problemsSubtitle(course))
                Spacer()
                Button(.quizProblemsAdd) { adding = true }.buttonStyle(.prominent)
            }
            ForEach(sets) { set in setBlock(set, units: units).linkTarget(set.id) }

            if sets.isEmpty {
                EmptyLine(String(localized: .quizProblemsEmpty))
            } else {
                Block(String(localized: .quizByUnit)) {
                    let (shown, byUnit) = model.problemsByUnit(course)
                    Card {
                        if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .quizProblemsNoUnits)) } }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                            TallyRow(
                                title: unit.title, tally: byUnit[unit.id]!, items: { .quizProblemsItems($0) }, last: i == shown.count - 1)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { ProblemSetSheet(workspace: model.workspace, course: course) }
        .confirming($model.pending)
    }

    func setBlock(_ set: ProblemSet, units: [FolioDomain.Unit]) -> some View {
        Block(
            title: set.title, note: model.summary(set),
            trailing: {
                HStack(spacing: Theme.Space.m) {
                    if let m = model.material(set.materialId, in: course) { Button(.quizProblemsSheet) { open(m) }.buttonStyle(.ghost) }
                    if let m = model.material(set.solutionMaterialId, in: course) {
                        Button(.quizProblemsSolution) { open(m) }.buttonStyle(.ghost)
                    }
                    Menu {
                        ProblemSetMenu(courseId: course.id, set: set)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
                }
            }
        ) {
            Card(padding: Theme.Space.m) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(set.problems, id: \.number) { problem in
                        let history = model.history(set: set.id, number: problem.number)
                        let sheet = model.material(set.materialId, in: course)
                        ProblemCell(
                            set: set, problem: problem, history: history, units: units,
                            linked: model.linkedTitles(problem, units: units), historyLine: model.historyLine(history),
                            openSheet: sheet.map { m in
                                {
                                    openLink(
                                        AppLink(.material, m.id, anchor: problem.page.map { AppLink.Anchor.page($0) }), course: course.id)
                                }
                            }
                        ) { verdict in
                            model.record(verdict, set: set.id, number: problem.number, in: course)
                        } toggleUnit: { unit in
                            model.toggle(unit, set: set.id, problem: problem, in: course)
                        }
                    }
                }
            }
        }
        .contextMenu { ProblemSetMenu(courseId: course.id, set: set) }
    }

    func open(_ m: FolioDomain.Material) {
        openLink(AppLink(.material, m.id), course: course.id)
    }
}
