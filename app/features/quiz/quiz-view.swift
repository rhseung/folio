import FolioDomain
import SwiftUI

struct QuizView: View {
    let course: LoadedCourse
    @Binding var section: CourseSection
    @State private var model: QuizModel

    init(workspace: Workspace, course: LoadedCourse, section: Binding<CourseSection>) {
        _model = State(initialValue: QuizModel(workspace: workspace))
        self.course = course
        _section = section
    }

    var body: some View {
        Group {
            switch section {
            case .quizCards: QuizCardsView(course: course, model: model)
            case .quizStats: QuizStatsView(course: course, model: model, solve: solve)
            case .quizProblems: ProblemSetsView(course: course, model: model)
            default: QuizSolveView(course: course, quiz: model, showCards: { section = .quizCards })
            }
        }
        .background(Theme.Palette.page)
        .task(id: course.id) { model.load(course) }
        .onChange(of: section) { _, new in if new != .quizSolve { model.request = nil } }
        .sheet(item: $model.generating) { unit in
            GenerateCardsSheet(workspace: model.workspace, course: course, unit: unit) { model.load(course) }
        }
    }

    func solve(_ request: SolveRequest) {
        model.request = request
        section = .quizSolve
    }
}

extension LoadedCourse {
    /// Units in outline order. Sorting by `order` alone interleaves the subunits of different chapters, which number from 1 each.
    var outline: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(file.units) }

    var unitOptions: [PickOption<UUID>] { outline.map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) } }
}

extension Verdict {
    var label: String {
        switch self {
        case .correct: String(localized: .quizVerdictCorrect)
        case .partial: String(localized: .quizVerdictPartial)
        case .wrong: String(localized: .quizVerdictWrong)
        }
    }

    var tone: Tone {
        switch self {
        case .correct: .success
        case .partial: .warning
        case .wrong: .danger
        }
    }
}

extension CardType {
    static let editable: [CardType] = [.free, .proof, .fill, .choice, .trueFalse, .handwritten]

    var label: String {
        switch self {
        case .free: String(localized: .quizCardTypeFree)
        case .trueFalse: String(localized: .quizCardTypeTrueFalse)
        case .choice: String(localized: .quizCardTypeChoice)
        case .fill: String(localized: .quizCardTypeFill)
        case .proof: String(localized: .quizCardTypeProof)
        case .handwritten: String(localized: .quizCardTypeHandwritten)
        }
    }
}

extension CardCategory {
    var label: String {
        switch self {
        case .definition: String(localized: .quizCategoryDefinition)
        case .theorem: String(localized: .quizCategoryTheorem)
        case .proof: String(localized: .quizCategoryProof)
        case .counterexample: String(localized: .quizCategoryCounterexample)
        case .computation: String(localized: .quizCategoryComputation)
        case .concept: String(localized: .quizCategoryConcept)
        case .design: String(localized: .quizCategoryDesign)
        }
    }
}

extension QuizOrder {
    var label: String {
        switch self {
        case .unitOrder: String(localized: .quizOrderUnitOrder)
        case .random: String(localized: .quizOrderRandom)
        case .wrongFirst: String(localized: .quizOrderWrongFirst)
        }
    }
}

extension WrongTally {
    var accuracyText: String { accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "-" }
}

struct MissingKeyNotice: View {
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        NoticeCard(title: String(localized: .quizMissingKeyTitle), detail: String(localized: .quizMissingKeyDetail),
                   systemImage: "key.fill") {
            Button(.quizMissingKeyOpenSettings) { showSettings(.claude) }.buttonStyle(.ghost)
        }
    }
}

extension Date {
    var monthDay: String { formatted(.dateTime.month().day()) }
}

extension LocalDate {
    var short: String { String(localized: .commonMonthDay(month, day)) }
}
