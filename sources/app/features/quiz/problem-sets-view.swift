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

struct ProblemSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProblemSetDraftModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: ProblemSetDraftModel(workspace: workspace, course: course))
    }

    var body: some View {
        let pdfOptions = model.pdfOptions
        SheetForm(title: String(localized: .quizProblemsAddTitle), confirm: String(localized: .commonAdd), disabled: !model.canAdd) {
            FormRow(label: String(localized: .quizProblemsFieldTitle)) {
                InlineField(String(localized: .quizProblemsFieldTitleExample), text: $model.title)
            }
            FormRow(label: String(localized: .quizProblemsSheet), detail: model.sheetDetail) {
                SearchSelect(selection: $model.problemId, options: pdfOptions)
            }
            FormRow(label: String(localized: .quizProblemsSolution)) { SearchSelect(selection: $model.solutionId, options: pdfOptions) }
            FormRow(label: String(localized: .quizProblemsFieldNumbers), detail: model.numbersDetail) {
                TextField("1-10", text: $model.numbers).pill(width: 160)
            }
            FormRow(label: String(localized: .quizUnit), detail: String(localized: .quizProblemsUnitsDetail), last: true) {
                SearchMultiSelect(selection: $model.unitIds, options: model.course.unitOptions, placeholder: String(localized: .commonNone))
            }
        } onConfirm: {
            model.add()
            dismiss()
        }
    }
}

struct ProblemCell: View {
    @Environment(\.accent) private var accent
    let set: ProblemSet
    let problem: ProblemSet.Problem
    let history: AttemptHistory
    let units: [FolioDomain.Unit]
    let linked: String
    let historyLine: String
    let openSheet: (() -> Void)?
    let mark: (Verdict) -> Void
    let toggleUnit: (UUID) -> Void
    @State private var open = false

    var body: some View {
        let status = WrongFlow.status(history)
        let (fill, ink): (Color, Color) =
            switch status {
            case .open: (Theme.Palette.dangerFill, Theme.Palette.danger)
            case .resolved: (accent.tint, accent.ink)
            case .neverWrong:
                history.isEmpty
                    ? (Theme.Palette.fill, Theme.Palette.textSecondary)
                    : (Theme.Palette.success.opacity(Theme.Opacity.tint), Theme.Palette.success)
            }
        let correct = WrongFlow.isOpen(status) ? String(localized: .quizProblemsResolve) : Verdict.correct.label
        Button {
            open = true
        } label: {
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
        .help(linked)
        .contextMenu {
            ItemMenu(
                source: ProblemMenuSource(
                    problem: problem, units: units, correct: correct, openSheet: openSheet, mark: mark, toggleUnit: toggleUnit))
        }
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(.quizProblemsCellTitle(set.title, problem.number)).font(Theme.Typeface.bodyStrong)
                HStack(spacing: Theme.Space.s) {
                    Button(correct) {
                        mark(.correct); open = false
                    }
                    Button(Verdict.partial.label) {
                        mark(.partial); open = false
                    }
                    Button(Verdict.wrong.label) {
                        mark(.wrong); open = false
                    }
                }
                if !history.isEmpty {
                    Text(historyLine)
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Space.l)
        }
    }
}
