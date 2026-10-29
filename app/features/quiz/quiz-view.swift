import FolioDomain
import SwiftUI

/// The course's cards and attempts, read once and re-read after each write so every tab shows the same numbers.
@MainActor @Observable
final class QuizModel {
    var cards: [QuizCard] = []
    var attempts: [Attempt<QuizAttemptEvent>] = []
    var problemAttempts: [Attempt<ProblemAttemptEvent>] = []
    private(set) var history: [UUID: AttemptHistory] = [:]
    private(set) var problemHistory: [String: AttemptHistory] = [:]

    func load(_ workspace: Workspace, _ course: LoadedCourse) {
        cards = workspace.quizCards(course)
        attempts = workspace.attempts(QuizAttemptEvent.self, in: course)
        problemAttempts = workspace.attempts(ProblemAttemptEvent.self, in: course)
        history = Dictionary(grouping: attempts, by: \.event.cardId).mapValues { $0.map { ($0.day, $0.event.verdict) } }
        problemHistory = Dictionary(grouping: problemAttempts) { Self.key($0.event.problemSetId, $0.event.number) }
            .mapValues { $0.map { ($0.day, $0.event.verdict) } }
    }

    static func key(_ set: UUID, _ number: String) -> String { "\(set.uuidString)/\(number)" }

    func history(of card: UUID) -> AttemptHistory { history[card] ?? [] }
    func history(set: UUID, number: String) -> AttemptHistory { problemHistory[Self.key(set, number)] ?? [] }
}

struct SolveRequest: Equatable {
    var id = UUID()
    var scope: QuizScope
    var label: String
    var order: QuizOrder = .unitOrder
}

struct QuizView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    @Binding var section: CourseSection
    @State private var model = QuizModel()
    @State private var request: SolveRequest?
    @State private var generating: FolioDomain.Unit?

    var body: some View {
        Group {
            switch section {
            case .quizCards: QuizCardsView(course: course, model: model, generate: { generating = $0 })
            case .quizStats: QuizStatsView(course: course, model: model, solve: solve)
            case .quizProblems: ProblemSetsView(course: course, model: model)
            default: QuizSolveView(course: course, model: model, request: request, showCards: { section = .quizCards })
            }
        }
        .background(Theme.Palette.page)
        .task(id: course.id) { model.load(workspace, course) }
        // A request is for the solve screen it opens; kept, it restarted that deck whenever 풀기 was chosen again.
        .onChange(of: section) { _, new in if new != .quizSolve { request = nil } }
        .sheet(item: $generating) { unit in
            GenerateCardsSheet(course: course, unit: unit) { model.load(workspace, course) }
        }
    }

    func solve(_ request: SolveRequest) {
        self.request = request
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
        case .correct: "맞음"
        case .partial: "애매"
        case .wrong: "틀림"
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
        case .free: "서술형"
        case .trueFalse: "참거짓"
        case .choice: "객관식"
        case .fill: "빈칸"
        case .proof: "증명"
        case .handwritten: "손풀이"
        }
    }
}

extension CardCategory {
    var label: String {
        switch self {
        case .definition: "정의"
        case .theorem: "정리"
        case .proof: "증명"
        case .counterexample: "반례"
        case .computation: "계산"
        case .concept: "개념"
        case .design: "설계"
        }
    }
}

extension QuizOrder {
    var label: String {
        switch self {
        case .unitOrder: "단원 순서"
        case .random: "무작위"
        case .wrongFirst: "오답 우선"
        }
    }
}

extension WrongTally {
    var accuracyText: String { accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "-" }
}

struct MissingKeyNotice: View {
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        NoticeCard(title: "Claude가 연결되지 않았습니다",
                   detail: "설정의 Claude 항목에서 Claude Code 구독이나 API 키를 연결하면 쓸 수 있습니다. 그 전에는 직접 만들고 직접 채점할 수 있습니다.",
                   systemImage: "key.fill") {
            Button("설정 열기") { showSettings(.claude) }.buttonStyle(.ghost)
        }
    }
}

extension Date {
    var monthDay: String { formatted(.dateTime.month().day()) }
}

extension LocalDate {
    var short: String { "\(month)월 \(day)일" }
}
