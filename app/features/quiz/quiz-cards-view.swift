import FolioActions
import FolioAI
import FolioDomain
import SwiftUI

/// Cards in the unit outline: a chapter per block, each unit a row with its cards under it (docs/SPEC.md "카드 만들기").
struct QuizCardsView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let model: QuizModel
    let generate: (FolioDomain.Unit) -> Void
    @State private var editing: CardDraft?
    @State private var pendingDelete: QuizCard?

    enum Entry: Identifiable {
        case unit(FolioDomain.Unit, depth: Int)
        case card(QuizCard, depth: Int)
        var id: UUID {
            switch self {
            case .unit(let u, _): u.id
            case .card(let c, _): c.id
            }
        }
    }

    var body: some View {
        let outline = course.outline
        let cards = Dictionary(grouping: model.cards, by: \.unitId)
        let open = model.cards.filter { WrongFlow.isOpen(WrongFlow.status(model.history(of: $0.id))) }.count
        Page {
            PageHeader(title: "퀴즈 카드", subtitle: (["카드 \(model.cards.count)장", "단원 \(outline.count)개"] + (open > 0 ? ["오답 \(open)장"] : [])).joined(separator: " · "))
            if outline.isEmpty { EmptyLine("카드는 단원에 속합니다. 단원 화면에서 단원을 먼저 만드세요.") }
            ForEach(UnitsView.groups(outline)) { group in
                let entries = (group.root.map { cards[$0.id] ?? [] } ?? []).map { Entry.card($0, depth: 0) }
                    + group.rows.flatMap { row in [Entry.unit(row.unit, depth: row.depth)] + (cards[row.unit.id] ?? []).map { .card($0, depth: row.depth + 1) } }
                if let root = group.root {
                    let count = ([root.id] + group.rows.map(\.unit.id)).reduce(0) { $0 + (cards[$1]?.count ?? 0) }
                    Block(title: root.title, note: "\(count)장", trailing: { addMenu(root) }) { Card { rows(entries, cards: cards) } }
                        .contextMenu { addItems(root) }
                } else {
                    Card { rows(entries, cards: cards) }
                }
            }
        }
        .sheet(item: $editing) { draft in
            CardEditorSheet(course: course, draft: draft, units: course.file.units) { model.load(workspace, course) }
        }
        .confirmationDialog("이 카드를 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("삭제", role: .destructive) {
                if let card = pendingDelete { workspace.run(QuizCardRemove(course: course.id, unit: card.unitId, card: card.id)) }
                model.load(workspace, course)
                pendingDelete = nil
            }
        } message: {
            Text("지난 풀이 기록은 로그에 남습니다.")
        }
    }

    func rows(_ entries: [Entry], cards: [UUID: [QuizCard]]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
            let last = i == entries.count - 1
            switch entry {
            case .unit(let unit, let depth):
                let n = cards[unit.id]?.count ?? 0
                CardRow(last: last) {
                    Text(unit.title).font(n > 0 ? Theme.Typeface.bodyStrong : Theme.Typeface.body).lineLimit(1)
                    Text(n > 0 ? "\(n)장" : "카드 없음").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: Theme.Space.m)
                    addMenu(unit)
                }
                .padding(.leading, CGFloat(depth) * Theme.Space.xl)
                .contextMenu { addItems(unit) }
            case .card(let card, let depth):
                CardRow(last: last) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(markdown(card.prompt)).lineLimit(2)
                        Text([card.type.label, card.category.label, card.source == .ai ? "Claude" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.m)
                    if WrongFlow.isOpen(WrongFlow.status(model.history(of: card.id))) { Chip("오답", tone: .danger) }
                }
                .padding(.leading, CGFloat(depth) * Theme.Space.xl)
                .opens { editing = CardDraft(card) }
                .help("카드 편집")
                .contextMenu {
                    Button("편집") { editing = CardDraft(card) }
                    Divider()
                    Button("삭제…", role: .destructive) { pendingDelete = card }
                }
            }
        }
    }

    @ViewBuilder func addItems(_ unit: FolioDomain.Unit) -> some View {
        Button("직접 추가") { editing = CardDraft(unitId: unit.id) }
        Button("Claude로 만들기") { generate(unit) }
    }

    func addMenu(_ unit: FolioDomain.Unit) -> some View {
        Menu { addItems(unit) } label: { Image(systemName: "plus") }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
            .foregroundStyle(Theme.Palette.textSecondary)
            .help("\(unit.title)에 카드 추가")
    }
}

/// The editable fields of a card; `original` is nil for a new one.
struct CardDraft: Identifiable {
    var id = UUID()
    var original: QuizCard?
    var unitId: UUID
    var type: CardType = .free
    var category: CardCategory = .definition
    var prompt = ""
    var answer = ""
    var options = ""
    var rubric = ""

    init(unitId: UUID) {
        self.unitId = unitId
    }

    init(_ card: QuizCard) {
        original = card
        unitId = card.unitId
        type = card.type
        category = card.category
        prompt = card.prompt
        answer = card.answer
        options = card.type == .choice ? card.options.joined(separator: "\n") : ""
        rubric = card.rubric.joined(separator: "\n")
    }

    var optionList: [String] {
        switch type {
        case .trueFalse: QuizCard.trueFalseOptions
        case .choice: lines(options)
        default: []
        }
    }

    var isValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !answer.isEmpty
            && (!(type == .choice || type == .trueFalse) || optionList.contains(answer))
    }

    func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func card(device: DeviceID) -> QuizCard {
        var card = original ?? QuizCard(device: device, at: .now, unitId: unitId, type: type, category: category, prompt: prompt, answer: answer)
        card.unitId = unitId
        card.type = type
        card.category = category
        card.prompt = prompt
        card.answer = answer
        card.options = optionList
        card.rubric = lines(rubric)
        card.touch(by: device, at: .now)
        return card
    }
}

struct CardEditorSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    @State var draft: CardDraft
    let units: [FolioDomain.Unit]
    let saved: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        SheetForm(title: draft.original == nil ? "카드 추가" : "카드 편집", confirm: "저장", disabled: !draft.isValid, carded: false,
                  deleteTitle: draft.original == nil ? nil : "카드 삭제", onDelete: { confirmingDelete = true }) {
            Card {
                FormRow(label: "단원") { SearchSelect(selection: $draft.unitId, options: UnitTree.outline(units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }) }
                // "유형" is the category, as the solve filter and the statistics call it (docs/SPEC.md "풀기 설정").
                FormRow(label: "유형") { ChoiceMenu(selection: $draft.category, options: CardCategory.allCases.map { ($0, $0.label) }) }
                FormRow(label: "형식", last: true) { ChoiceMenu(selection: $draft.type, options: CardType.editable.map { ($0, $0.label) }) }
            }
            FormTextArea(label: "문제", text: $draft.prompt, height: 80)
            switch draft.type {
            case .choice:
                FormTextArea(label: "선택지", detail: "한 줄에 하나씩", text: $draft.options, height: 70)
                Card {
                    FormRow(label: "정답", last: true) {
                        ChoiceMenu(selection: $draft.answer, options: [("", "고르세요")] + draft.optionList.map { ($0, $0) })
                    }
                }
            case .trueFalse:
                Card { FormRow(label: "정답", last: true) { ChoiceMenu(selection: $draft.answer, options: [("", "고르세요")] + QuizCard.trueFalseOptions.map { ($0, $0) }) } }
            default:
                FormTextArea(label: "모범 답안", text: $draft.answer, height: 80)
            }
            FormTextArea(label: "채점 기준", detail: "한 줄에 하나씩, 빠지면 틀리는 요소", text: $draft.rubric, height: 56)
        } onConfirm: {
            let card = draft.card(device: workspace.device)
            guard workspace.run(QuizCardSave(course: course.id, cards: [card], movedFrom: draft.original?.unitId)) != nil else { return }
            saved()
            dismiss()
        }
        .confirmationDialog("이 카드를 삭제할까요?", isPresented: $confirmingDelete) {
            Button("삭제", role: .destructive) {
                if let card = draft.original { workspace.run(QuizCardRemove(course: course.id, unit: card.unitId, card: card.id)) }
                saved()
                dismiss()
            }
        } message: {
            Text("지난 풀이 기록은 로그에 남습니다.")
        }
    }
}

/// Asks Claude for cards on one unit and saves only the candidates the user keeps (docs/SPEC.md "카드 만들기").
struct GenerateCardsSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    let saved: () -> Void
    @State private var count = 5
    @State private var type: CardType?
    @State private var candidates: [QuizCard] = []
    @State private var kept: Set<UUID> = []
    @State private var busy = false
    @State private var failure: String?
    @State private var keyRejected = false
    var hasKey: Bool { workspace.claudeReady && !keyRejected }

    var body: some View {
        SheetForm(title: "\(unit.title) · Claude로 카드 만들기", confirm: candidates.isEmpty ? "만들기" : "고른 \(kept.count)장 저장",
                  disabled: !hasKey || busy || (!candidates.isEmpty && kept.isEmpty),
                  note: candidates.isEmpty ? "이 단원의 노트와 과목 요약을 Claude에 보냅니다" : "저장하지 않은 후보는 버립니다") {
            if !hasKey {
                MissingKeyNotice().padding(Theme.Space.m)
            } else if candidates.isEmpty {
                FormRow(label: "개수") { ChoiceMenu(selection: $count, options: [3, 5, 10, 15].map { ($0, "\($0)장") }) }
                FormRow(label: "형식", last: busy == false && failure == nil) {
                    ChoiceMenu(selection: $type, options: [(CardType?.none, "섞어서")] + [CardType.free, .proof, .choice, .trueFalse, .fill].map { (Optional($0), $0.label) })
                }
                if busy { CardRow(last: failure == nil) { ProgressView().controlSize(.small); Text("Claude가 카드를 만드는 중").foregroundStyle(Theme.Palette.textSecondary) } }
                if let failure { CardRow(last: true) { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) } }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { i, card in
                            let on = kept.contains(card.id)
                            Button {
                                if on { kept.remove(card.id) } else { kept.insert(card.id) }
                            } label: {
                                CardRow(last: i == candidates.count - 1) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(markdown(card.prompt)).lineLimit(4)
                                        Text("\(card.type.label) · \(card.category.label) · 답: \(card.answer)").lineLimit(2)
                                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        } onConfirm: {
            if candidates.isEmpty { make() } else { save() }
        }
    }

    func make() {
        busy = true
        failure = nil
        let client = workspace.claude(for: course)
        let context = workspace.cardContext(course, unit: unit)
        let (unitId, device, title, count, type) = (unit.id, workspace.device, unit.title, count, type)
        Task {
            do {
                let drafts = try await client.makeCards(unitTitle: title, count: count, type: type, context: context)
                candidates = drafts.compactMap { $0.card(unitId: unitId, device: device, at: .now) }
                kept = Set(candidates.map(\.id))
                if candidates.isEmpty { failure = "쓸 수 있는 카드가 나오지 않았습니다. 다시 시도해 보세요." }
            } catch ClaudeError.missingAPIKey {
                keyRejected = true
            } catch {
                failure = "카드를 만들지 못했습니다. (\(error))"
            }
            busy = false
        }
    }

    func save() {
        let picked = candidates.filter { kept.contains($0.id) }
        guard workspace.run(QuizCardSave(course: course.id, cards: picked)) != nil else { return }
        saved()
        dismiss()
    }
}
