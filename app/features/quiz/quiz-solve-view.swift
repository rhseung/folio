import FolioActions
import FolioAI
import FolioDomain
import SwiftUI

struct QuizSolveView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let model: QuizModel
    let request: SolveRequest?
    let showCards: () -> Void

    enum Grading: Hashable { case claude, mine }

    /// A graded answer not yet written to the log. It is written when the user moves on, so a changed verdict
    /// becomes one attempt marked as overridden instead of two.
    struct Pending {
        var cardId: UUID
        var answer: String
        var verdict: Verdict
        let original: Verdict
        let grader: QuizAttemptEvent.Grader
        var missing: [String] = []
        var feedback: String?
        var byClaude = false
    }

    @State private var scope = QuizScope()
    @State private var order: QuizOrder = .unitOrder
    @State private var grading: Grading = .claude
    @State private var label = ""
    @State private var deck: [QuizCard] = []
    @State private var index = 0
    @State private var started = false
    @State private var round: [Verdict] = []
    @State private var answer = ""
    @State private var revealed = false
    @State private var pending: Pending?
    @State private var busy = false
    @State private var failure: String?
    @State private var missingKey = false

    var body: some View {
        // Two panes, not three: the card's history and the round tally sit under the card, so the card keeps its width
        // when the Claude inspector opens. The pane and divider run up under the toolbar like the course column.
        HStack(spacing: 0) {
            scopePane.frame(width: 250).background(Theme.Palette.window.ignoresSafeArea())
            ColumnDivider()
            center.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onAppear {
            missingKey = !workspace.claudeReady
            if missingKey { grading = .mine }
            if scope.unitIds.isEmpty { scope.unitIds = Set(units.map(\.id)) }
        }
        #if DEBUG && os(macOS)
        // After the cards load: started from onAppear, the snapshot showed an empty deck while the pane counted cards.
        .onChange(of: model.cards.count, initial: true) { _, n in
            if SnapshotDriver.directory != nil, !started, n > 0 { order = .wrongFirst; start(label: "고른 범위") }
        }
        #endif
        .onChange(of: request?.id, initial: true) { _, _ in
            guard let request else { return }
            scope = request.scope
            order = request.order
            start(label: request.label)
        }
        .onDisappear(perform: commit)
    }

    // MARK: Scope

    var units: [FolioDomain.Unit] { course.outline.map(\.unit) }

    var scopePane: some View {
        let byUnit = QuizStats.tally(model.cards, keys: { [$0.unitId] }, history: { model.history(of: $0.id) })
        let today = workspace.today
        let wrong = model.cards.filter { WrongFlow.isDue(model.history(of: $0.id), today: today) }
        let exam = course.file.exams.filter { ($0.start ?? .distantPast) > .now && !$0.scopeUnitIds.isEmpty }.min { $0.start! < $1.start! }
        let examCards = exam.map { e in model.cards.filter { e.scopeUnitIds.contains($0.unitId) }.count } ?? 0
        let reviewUnits = Set(workspace.reviewQueue(now: .now).filter { $0.courseId == course.id }.map(\.item.unitId))
        let reviewCards = model.cards.filter { reviewUnits.contains($0.unitId) }.count
        // Only units with cards can be picked; the rest are counted and sent to the cards screen.
        let groups = UnitsView.groups(course.outline).compactMap { g -> (title: String?, units: [FolioDomain.Unit])? in
            let rows = ((g.root.map { [$0] } ?? []) + g.rows.map(\.unit)).filter { byUnit[$0.id] != nil }
            return rows.isEmpty ? nil : (g.root?.title, rows)
        }
        let withCards = Set(byUnit.keys)
        let empty = units.filter { !withCards.contains($0.id) }.count
        let preview = buildDeck()
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption("바로가기")
                    VStack(spacing: Theme.Space.xxs) {
                        shortcut("오답만", detail: "\(wrong.count)장", disabled: wrong.isEmpty) {
                            scope = QuizScope(unitIds: Set(units.map(\.id)), onlyWrong: true)
                            start(label: "오답만")
                        }
                        shortcut("시험 범위 전체", detail: exam.map { "\($0.title) · \(examCards)장" } ?? "다가오는 시험 없음", disabled: examCards == 0) {
                            scope = QuizScope(unitIds: Set(exam?.scopeUnitIds ?? []))
                            start(label: "시험 범위 전체")
                        }
                        shortcut("오늘 복습 단원", detail: "\(reviewUnits.count)단원 · \(reviewCards)장", disabled: reviewCards == 0) {
                            scope = QuizScope(unitIds: reviewUnits)
                            start(label: "오늘 복습 단원")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Caption("단원")
                        Spacer()
                        if !withCards.isEmpty {
                            let all = withCards.isSubset(of: scope.unitIds)
                            Button(all ? "모두 해제" : "모두 선택") { scope.unitIds = all ? [] : Set(units.map(\.id)) }
                                .buttonStyle(.ghost).font(Theme.Typeface.caption)
                        }
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            if let title = group.title {
                                Text(title).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                                    .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.xs)
                            }
                            ForEach(group.units) { unit in unitRow(unit, tally: byUnit[unit.id]!) }
                        }
                    }
                    if empty > 0 {
                        HStack(spacing: Theme.Space.xs) {
                            Text(withCards.isEmpty ? "카드가 아직 없습니다" : "카드 없는 단원 \(empty)개").foregroundStyle(Theme.Palette.textTertiary)
                            Spacer(minLength: 0)
                            Button("카드 만들기", action: showCards).buttonStyle(.ghost)
                        }
                        .font(Theme.Typeface.caption)
                        .padding(.horizontal, Theme.Space.s)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption("유형")
                    FlowChips(items: CardCategory.allCases, selected: scope.categories, label: { $0.label }) { c in
                        if scope.categories.contains(c) { scope.categories.remove(c) } else { scope.categories.insert(c) }
                    }
                }

                VStack(spacing: Theme.Space.s) {
                    HStack { Text("순서"); Spacer(); ChoiceMenu(selection: $order, options: QuizOrder.allCases.map { ($0, $0.label) }) }
                    HStack {
                        Text("채점")
                        Spacer()
                        ChoiceMenu(selection: $grading, options: missingKey ? [(.mine, "직접")] : [(.claude, "Claude"), (.mine, "직접")])
                    }
                }
            }
            .padding(Theme.Space.l)
        }
        // The start button stays in view: below forty units it was a scroll away from every choice it starts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                let categories = scope.categories.isEmpty ? "모든 유형" : CardCategory.allCases.filter(scope.categories.contains).map(\.label).joined(separator: ", ")
                Text("\(scope.unitIds.intersection(withCards).count)단원 · \(categories) · \(preview.count)장")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                Button(started ? "이 범위로 다시 시작" : "이 범위로 시작") { start(label: "고른 범위") }
                    .buttonStyle(.pointing(.borderedProminent))
                    .frame(maxWidth: .infinity)
                    .disabled(preview.isEmpty)
            }
            .padding(Theme.Space.l)
            .background(Theme.Palette.window)
            .overlay(alignment: .top) { Theme.Palette.lineSoft.frame(height: 1) }
        }
        .background(Theme.Palette.window)
    }

    func shortcut(_ title: String, detail: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .padding(Theme.Inset.listRow)
            .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    func unitRow(_ unit: FolioDomain.Unit, tally: WrongTally) -> some View {
        let on = scope.unitIds.contains(unit.id)
        return Button {
            if on { scope.unitIds.remove(unit.id) } else { scope.unitIds.insert(unit.id) }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
                    Text(unit.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(["\(tally.items)장", tally.accuracy == nil ? nil : "정답률 \(tally.accuracyText)", tally.open > 0 ? "오답 \(tally.open)" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(tally.open > 0 ? Theme.Palette.danger : Theme.Palette.textTertiary)
                    .padding(.leading, 22)
                Meter(value: tally.progress, height: 4).padding(.leading, 22)
            }
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.s)
            // The check carries the choice; tinting every chosen row (all of them, by default) made one solid slab.
            .background(on ? Theme.Palette.card : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu { Button(on ? "범위에서 빼기" : "범위에 넣기") { if on { scope.unitIds.remove(unit.id) } else { scope.unitIds.insert(unit.id) } } }
        .help("진도 \(Int((tally.progress * 100).rounded()))% · 푼 카드 \(tally.attempted) / \(tally.items)")
    }

    func buildDeck() -> [QuizCard] {
        var rng = SystemRandomNumberGenerator()
        return QuizDeck.build(cards: model.cards, units: units.map(\.id), scope: scope, order: order, history: model.history, today: workspace.today, using: &rng)
    }

    func start(label: String) {
        commit()
        self.label = label
        deck = buildDeck()
        index = 0
        round = []
        started = true
        resetAnswer()
    }

    func resetAnswer() {
        answer = ""
        revealed = false
        pending = nil
        failure = nil
        busy = false
    }

    // MARK: Card

    var current: QuizCard? { started && index < deck.count ? deck[index] : nil }

    @ViewBuilder var center: some View {
        if let card = current {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack {
                        Text("퀴즈 › \(label)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        Spacer()
                        if !round.isEmpty {
                            HStack(spacing: Theme.Space.s) {
                                ForEach([Verdict.correct, .partial, .wrong], id: \.self) { v in
                                    Text("\(v.label) \(round.filter { $0 == v }.count)").font(Theme.Typeface.caption).foregroundStyle(v.tone.foreground)
                                }
                            }
                            .monospacedDigit()
                            .help("이번 회차")
                        }
                        Text("\(index + 1) / \(deck.count)").font(Theme.Typeface.bodyStrong).monospacedDigit()
                        Button("끝내기") { commit(); index = deck.count }.buttonStyle(.ghost)
                    }
                    Meter(value: Double(index) / Double(max(deck.count, 1)), height: 4)
                    cardView(card)
                    history(of: card)
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else if started {
            finished
        } else {
            ContentUnavailableView {
                Label("범위를 고르고 시작하세요", systemImage: "rectangle.stack")
            } description: {
                Text(model.cards.isEmpty ? "카드 화면에서 직접 만들거나 Claude로 만들 수 있습니다." : "왼쪽에서 단원과 유형을 고르거나 바로가기를 누르세요.")
            } actions: {
                if model.cards.isEmpty { Button("카드 만들기", action: showCards) }
            }
        }
    }

    @ViewBuilder var finished: some View {
        // A shortcut can start a scope with no cards, and 끝내기 can come before any answer: neither solved anything.
        if round.isEmpty {
            ContentUnavailableView {
                Label(deck.isEmpty ? "이 범위에 풀 카드가 없습니다" : "푼 카드 없이 끝냈습니다", systemImage: "rectangle.stack")
            } description: {
                Text(deck.isEmpty ? "왼쪽에서 다른 단원이나 유형을 고르세요." : "왼쪽에서 범위를 고르고 다시 시작하세요.")
            }
        } else {
            solvedSummary
        }
    }

    var solvedSummary: some View {
        VStack(spacing: Theme.Space.l) {
            Text("\(round.count)장을 풀었습니다").font(Theme.Typeface.columnTitle)
            HStack(spacing: Theme.Space.s) {
                ForEach([Verdict.correct, .partial, .wrong], id: \.self) { v in Chip("\(v.label) \(round.filter { $0 == v }.count)", tone: v.tone) }
            }
            Button("같은 범위로 다시") { start(label: label) }.buttonStyle(.pointing(.borderedProminent))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func cardView(_ card: QuizCard) -> some View {
        Card(padding: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.s) {
                    Chip(card.category.label, tone: .accent)
                    Text(units.first { $0.id == card.unitId }?.title ?? "").font(Theme.Typeface.bodyStrong)
                    Spacer()
                    Text(card.type.label + (card.source == .ai ? " · Claude가 만든 카드" : ""))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(markdown(card.prompt)).font(Theme.Typeface.bodyLarge).lineSpacing(3).textSelection(.enabled)

                if card.gradesInstantly {
                    options(card)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Caption("내 답안")
                        TextEditor(text: $answer)
                            .font(.system(size: 14)) // design: one-off, the answer sits a step under the 15pt prompt
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Space.s)
                            .frame(minHeight: 120)
                            .background(Theme.Palette.fill.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.control))
                            .disabled(pending != nil || busy)
                        if pending == nil && !revealed {
                            HStack {
                                if busy { ProgressView().controlSize(.small); Text("Claude가 채점하는 중").foregroundStyle(Theme.Palette.textSecondary) }
                                Spacer()
                                if grading == .claude {
                                    Button("직접 채점") { revealed = true }.buttonStyle(.ghost)
                                    Button("Claude 채점") { grade(card) }
                                        .buttonStyle(.pointing(.borderedProminent))
                                        .keyboardShortcut(.return, modifiers: .command)
                                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                                } else {
                                    Button("모범 답안 보기") { revealed = true }
                                        .buttonStyle(.pointing(.borderedProminent))
                                        .keyboardShortcut(.return, modifiers: .command)
                                }
                            }
                        }
                        if let failure {
                            if missingKey { MissingKeyNotice() } else { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
                        }
                    }
                }

                if let pending { result(card, pending) } else if revealed { selfGrade(card) }
            }
        }
    }

    func options(_ card: QuizCard) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(card.options, id: \.self) { option in
                let chosen = pending?.answer == option
                let tone: Tone? = pending == nil ? nil : option == card.answer ? .success : chosen ? .danger : nil
                Button {
                    let v = card.verdict(choosing: option)
                    pending = Pending(cardId: card.id, answer: option, verdict: v, original: v, grader: .self)
                } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if let tone { Image(systemName: tone == .success ? "checkmark" : "xmark").foregroundStyle(tone.foreground) }
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(tone == .success ? Theme.Palette.success.opacity(Theme.Opacity.tint) : tone == .danger ? Theme.Palette.dangerFill : Theme.Palette.fill.opacity(0.6),
                                in: .rect(cornerRadius: Theme.Radius.control))
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .disabled(pending != nil)
            }
        }
    }

    func selfGrade(_ card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            modelAnswer(card)
            verdictButtons(selected: nil, note: "모범 답안과 비교해 판정하세요") { v in
                pending = Pending(cardId: card.id, answer: answer, verdict: v, original: v, grader: .self)
            }
        }
    }

    func result(_ card: QuizCard, _ p: Pending) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Text(p.byClaude ? "Claude 채점" : card.gradesInstantly ? "자동 채점" : "직접 채점").font(Theme.Typeface.bodyStrong)
                    Chip(p.original.label, tone: p.original.tone)
                    if !card.rubric.isEmpty && p.byClaude {
                        Text("채점 기준 \(card.rubric.count)개 중 \(card.rubric.count - p.missing.count)개 충족")
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                if p.byClaude {
                    ForEach(card.rubric, id: \.self) { item in
                        let missed = p.missing.contains(item)
                        Label(item, systemImage: missed ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(missed ? Theme.Palette.danger : Theme.Palette.success)
                    }
                    ForEach(p.missing.filter { !card.rubric.contains($0) }, id: \.self) { item in
                        Label("누락 · \(item)", systemImage: "xmark.circle").foregroundStyle(Theme.Palette.danger)
                    }
                }
                if let feedback = p.feedback, !feedback.isEmpty { Text(feedback).foregroundStyle(Theme.Palette.textSecondary).lineSpacing(2) }
            }
            if !card.gradesInstantly { modelAnswer(card) }
            verdictButtons(selected: p.verdict, note: "판정을 바꾸면 내 판정으로 기록됩니다") { v in pending?.verdict = v }
            HStack {
                Spacer()
                Button(index + 1 < deck.count ? "다음 문제" : "마치기") { next() }
                    .buttonStyle(.pointing(.borderedProminent))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    func modelAnswer(_ card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("모범 답안").font(Theme.Typeface.label).foregroundStyle(accent.ink)
            Text(markdown(card.answer)).lineSpacing(3).textSelection(.enabled)
        }
        .padding(Theme.Inset.panel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.color.opacity(0.07), in: .rect(cornerRadius: Theme.Radius.control))
    }

    func verdictButtons(selected: Verdict?, note: String, pick: @escaping (Verdict) -> Void) -> some View {
        HStack(spacing: Theme.Space.s) {
            ForEach([Verdict.correct, .partial, .wrong], id: \.self) { v in
                Button { pick(v) } label: {
                    Text(v.label)
                        .font(Theme.Typeface.bodyStrong)
                        .foregroundStyle(selected == v ? Theme.Palette.onFill : v.tone.foreground)
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                        .background(selected == v ? v.tone.foreground : v.tone == .success ? Theme.Palette.success.opacity(Theme.Opacity.tint) : v.tone.fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
            }
            Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    func grade(_ card: QuizCard) {
        guard workspace.claudeReady else {
            missingKey = true
            failure = ""
            return
        }
        busy = true
        failure = nil
        let client = workspace.claude(for: course)
        let given = answer
        Task {
            do {
                let r = try await client.grade(question: card.prompt, modelAnswer: card.answer, rubric: card.rubric, answer: given, rules: "")
                let v = Verdict(rawValue: r.verdict.rawValue) ?? .wrong
                pending = Pending(cardId: card.id, answer: given, verdict: v, original: v, grader: .ai, missing: r.missing, feedback: r.feedback, byClaude: true)
            } catch ClaudeError.missingAPIKey {
                missingKey = true
                failure = ""
            } catch {
                failure = "채점하지 못했습니다. 직접 채점으로 판정할 수 있습니다. (\(error))"
            }
            busy = false
        }
    }

    func next() {
        commit()
        index += 1
        resetAnswer()
    }

    func commit() {
        guard let p = pending else { return }
        workspace.run(QuizRecord(course: course.id, attempt: QuizAttemptEvent(cardId: p.cardId, answer: p.answer.isEmpty ? nil : p.answer, verdict: p.verdict,
                                                                         grader: p.grader, missing: p.missing, overridden: p.verdict != p.original)))
        round.append(p.verdict)
        pending = nil
        model.load(workspace, course)
    }

    // MARK: History

    func history(of card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Caption("이 카드의 기록")
            let past = model.attempts.filter { $0.event.cardId == card.id }
            if past.isEmpty && pending == nil { EmptyLine("처음 푸는 카드입니다").font(Theme.Typeface.caption) }
            ForEach(Array(past.enumerated()), id: \.offset) { _, a in
                historyRow(a.event.verdict, overridden: a.event.overridden, detail: "\(a.at.monthDay) · " + (a.event.grader == .ai ? "Claude" : "직접") + (a.event.overridden ? " · 내가 바꿈" : ""))
            }
            if let pending { historyRow(pending.verdict, overridden: pending.verdict != pending.original, detail: "오늘 · 지금 답안") }
            status(model.history(of: card.id))
        }
        .padding(.top, Theme.Space.s)
    }

    func historyRow(_ verdict: Verdict, overridden: Bool, detail: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Chip(verdict.label, tone: verdict.tone)
            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
        }
    }

    @ViewBuilder func status(_ history: AttemptHistory) -> some View {
        switch WrongFlow.status(history) {
        case .open(let since):
            Text("\(since.short)부터 오답 목록에 있습니다").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
        case .resolved(_, let recheck?):
            Text("해결됨 · \(recheck.short)에 한 번 더 확인합니다").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
        case .resolved:
            Text("해결됨").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.success)
        case .neverWrong:
            EmptyView()
        }
    }
}

/// Math stays as TeX until KaTeX is bundled.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

struct FlowChips<Item: Hashable>: View {
    @Environment(\.accent) private var accent
    let items: [Item]
    let selected: Set<Item>
    let label: (Item) -> String
    let toggle: (Item) -> Void

    var body: some View {
        WrapLayout(spacing: Theme.Space.tight) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { toggle(item) } label: {
                    Text(label(item))
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .padding(Theme.Inset.toggle)
                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            for (i, x) in zip(row.indices, row.xs) {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat; var width: CGFloat = 0; var height: CGFloat = 0 }

    func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row(y: 0)]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows.removeLast()
            row.xs.append(row.indices.isEmpty ? 0 : row.width + spacing)
            row.width = row.xs.last! + size.width
            row.indices.append(i)
            row.height = max(row.height, size.height)
            rows.append(row)
        }
        return rows
    }
}
