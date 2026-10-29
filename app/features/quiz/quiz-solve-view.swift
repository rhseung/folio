import FolioDomain
import SwiftUI

struct QuizSolveView: View {
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    let showCards: () -> Void
    @State private var model: QuizSolveModel

    init(course: LoadedCourse, quiz: QuizModel, showCards: @escaping () -> Void) {
        _model = State(initialValue: QuizSolveModel(quiz: quiz))
        self.course = course
        self.showCards = showCards
    }

    var body: some View {
        // Two panes, not three: the card's history and the round tally sit under the card, so the card keeps its width
        // when the Claude inspector opens. The pane and divider run up under the toolbar like the course column.
        HStack(spacing: 0) {
            scopePane.frame(width: 250).background(Theme.Palette.window.ignoresSafeArea())
            ColumnDivider()
            center.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onAppear { model.prepare(course) }
        #if DEBUG && os(macOS)
        // After the cards load: started from onAppear, the snapshot showed an empty deck while the pane counted cards.
        .onChange(of: model.quiz.cards.count, initial: true) { _, n in
            if SnapshotDriver.directory != nil, !model.started, n > 0 { model.order = .wrongFirst; model.start(label: String(localized: .quizSolvePickedScope), course: course) }
        }
        #endif
        .onChange(of: model.quiz.request?.id, initial: true) { _, _ in
            guard let request = model.quiz.request else { return }
            model.apply(request, course: course)
        }
        .onDisappear { model.commit(course) }
    }

    // MARK: Scope

    var scopePane: some View {
        let pane = model.pane(course)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption(String(localized: .quizSolveShortcuts))
                    VStack(spacing: Theme.Space.xxs) {
                        shortcut(String(localized: .quizOnlyWrong), detail: String(localized: .quizCardCount(pane.wrong)), disabled: pane.wrong == 0) {
                            model.solveOnlyWrong(course)
                        }
                        shortcut(String(localized: .quizSolveExamScope), detail: model.examDetail(pane), disabled: pane.examCards == 0) {
                            model.solveExam(pane, course: course)
                        }
                        shortcut(String(localized: .quizSolveReviewUnits), detail: String(localized: .quizSolveReviewDetail(pane.reviewUnits.count, pane.reviewCards)),
                                 disabled: pane.reviewCards == 0) {
                            model.solveReview(pane, course: course)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Caption(String(localized: .quizUnit))
                        Spacer()
                        if !pane.withCards.isEmpty {
                            Button(model.allSelected(pane) ? .quizSolveDeselectAll : .quizSolveSelectAll) { model.toggleAll(pane, course: course) }
                                .buttonStyle(.ghost).font(Theme.Typeface.caption)
                        }
                    }
                    ForEach(Array(pane.groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            if let title = group.title {
                                Text(title).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                                    .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.xs)
                            }
                            ForEach(group.units) { unit in unitRow(unit, tally: pane.byUnit[unit.id]!) }
                        }
                    }
                    if pane.empty > 0 {
                        HStack(spacing: Theme.Space.xs) {
                            Text(model.emptyText(pane)).foregroundStyle(Theme.Palette.textTertiary)
                            Spacer(minLength: 0)
                            Button(.quizSolveMakeCards, action: showCards).buttonStyle(.ghost)
                        }
                        .font(Theme.Typeface.caption)
                        .padding(.horizontal, Theme.Space.s)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Caption(String(localized: .quizCategory))
                    FlowChips(items: CardCategory.allCases, selected: model.scope.categories, label: { $0.label }) { model.toggle($0) }
                }

                VStack(spacing: Theme.Space.s) {
                    HStack { Text(.quizSolveOrder); Spacer(); ChoiceMenu(selection: $model.order, options: QuizOrder.allCases.map { ($0, $0.label) }) }
                    HStack {
                        Text(.quizSolveGrading)
                        Spacer()
                        ChoiceMenu(selection: $model.grading, options: model.gradingOptions)
                    }
                }
            }
            .padding(Theme.Space.l)
        }
        // The start button stays in view: below forty units it was a scroll away from every choice it starts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(model.footer(pane))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                Button(model.started ? .quizSolveRestart : .quizSolveStart) { model.start(label: String(localized: .quizSolvePickedScope), course: course) }
                    .buttonStyle(.pointing(.borderedProminent))
                    .frame(maxWidth: .infinity)
                    .disabled(pane.preview == 0)
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
        let on = model.scope.unitIds.contains(unit.id)
        return Button { model.toggle(unit.id) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
                    Text(unit.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(model.unitDetail(tally))
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
        .contextMenu { Button(on ? .quizSolveExclude : .quizSolveInclude) { model.toggle(unit.id) } }
        .help(model.unitHelp(tally))
    }

    // MARK: Card

    @ViewBuilder var center: some View {
        if let card = model.current {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack {
                        Text(model.crumb).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        Spacer()
                        if !model.round.isEmpty {
                            HStack(spacing: Theme.Space.s) {
                                ForEach([Verdict.correct, .partial, .wrong], id: \.self) { v in
                                    Text(model.roundText(v)).font(Theme.Typeface.caption).foregroundStyle(v.tone.foreground)
                                }
                            }
                            .monospacedDigit()
                            .help(Text(.quizSolveRound))
                        }
                        Text("\(model.index + 1) / \(model.deck.count)").font(Theme.Typeface.bodyStrong).monospacedDigit()
                        Button(.quizSolveFinish) { model.finish(course) }.buttonStyle(.ghost)
                    }
                    Meter(value: Double(model.index) / Double(max(model.deck.count, 1)), height: 4)
                    cardView(card)
                    history(of: card)
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        } else if model.started {
            finished
        } else {
            ContentUnavailableView {
                Label(.quizSolvePickScope, systemImage: "rectangle.stack")
            } description: {
                Text(model.unstartedDetail)
            } actions: {
                if model.quiz.cards.isEmpty { Button(.quizSolveMakeCards, action: showCards) }
            }
        }
    }

    @ViewBuilder var finished: some View {
        // A shortcut can start a scope with no cards, and 끝내기 can come before any answer: neither solved anything.
        if model.round.isEmpty {
            ContentUnavailableView {
                Label(model.finishedTitle, systemImage: "rectangle.stack")
            } description: {
                Text(model.finishedDetail)
            }
        } else {
            solvedSummary
        }
    }

    var solvedSummary: some View {
        VStack(spacing: Theme.Space.l) {
            Text(.quizSolveSolved(model.round.count)).font(Theme.Typeface.columnTitle)
            HStack(spacing: Theme.Space.s) {
                ForEach([Verdict.correct, .partial, .wrong], id: \.self) { v in Chip(model.roundText(v), tone: v.tone) }
            }
            Button(.quizSolveAgain) { model.start(label: model.label, course: course) }.buttonStyle(.pointing(.borderedProminent))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func cardView(_ card: QuizCard) -> some View {
        Card(padding: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.s) {
                    Chip(card.category.label, tone: .accent)
                    Text(model.unitTitle(card, course: course)).font(Theme.Typeface.bodyStrong)
                    Spacer()
                    Text(model.typeText(card))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(markdown(card.prompt)).font(Theme.Typeface.bodyLarge).lineSpacing(3).textSelection(.enabled)

                if card.gradesInstantly {
                    options(card)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Caption(String(localized: .quizSolveMyAnswer))
                        TextEditor(text: $model.answer)
                            .font(.system(size: 14)) // design: one-off, the answer sits a step under the 15pt prompt
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Space.s)
                            .frame(minHeight: 120)
                            .background(Theme.Palette.fill.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.control))
                            .disabled(model.pending != nil || model.busy)
                        if model.pending == nil && !model.revealed {
                            HStack {
                                if model.busy { ProgressView().controlSize(.small); Text(.quizSolveGradingBusy).foregroundStyle(Theme.Palette.textSecondary) }
                                Spacer()
                                if model.grading == .claude {
                                    Button(.quizSolveGradeMine) { model.revealed = true }.buttonStyle(.ghost)
                                    Button(.quizSolveGradeClaude) { model.grade(card, course: course) }
                                        .buttonStyle(.pointing(.borderedProminent))
                                        .keyboardShortcut(.return, modifiers: .command)
                                        .disabled(!model.canGrade)
                                } else {
                                    Button(.quizSolveShowAnswer) { model.revealed = true }
                                        .buttonStyle(.pointing(.borderedProminent))
                                        .keyboardShortcut(.return, modifiers: .command)
                                }
                            }
                        }
                        if let failure = model.failure {
                            if model.missingKey { MissingKeyNotice() } else { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
                        }
                    }
                }

                if let pending = model.pending { result(card, pending) } else if model.revealed { selfGrade(card) }
            }
        }
    }

    func options(_ card: QuizCard) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(card.options, id: \.self) { option in
                let chosen = model.pending?.answer == option
                let tone: Tone? = model.pending == nil ? nil : option == card.answer ? .success : chosen ? .danger : nil
                Button { model.choose(option, on: card) } label: {
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
                .disabled(model.pending != nil)
            }
        }
    }

    func selfGrade(_ card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            modelAnswer(card)
            verdictButtons(selected: nil, note: String(localized: .quizSolveCompare)) { model.judge($0, on: card) }
        }
    }

    func result(_ card: QuizCard, _ p: QuizSolveModel.Pending) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Text(model.gradedTitle(card, p)).font(Theme.Typeface.bodyStrong)
                    Chip(p.original.label, tone: p.original.tone)
                    if !card.rubric.isEmpty && p.byClaude {
                        Text(model.rubricMet(card, p))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                if p.byClaude {
                    ForEach(card.rubric, id: \.self) { item in
                        let missed = p.missing.contains(item)
                        Label(item, systemImage: missed ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(missed ? Theme.Palette.danger : Theme.Palette.success)
                    }
                    ForEach(model.extraMissing(card, p), id: \.self) { item in
                        Label(String(localized: .quizSolveMissing(item)), systemImage: "xmark.circle").foregroundStyle(Theme.Palette.danger)
                    }
                }
                if let feedback = p.feedback, !feedback.isEmpty { Text(feedback).foregroundStyle(Theme.Palette.textSecondary).lineSpacing(2) }
            }
            if !card.gradesInstantly { modelAnswer(card) }
            verdictButtons(selected: p.verdict, note: String(localized: .quizSolveOverrideNote)) { model.pending?.verdict = $0 }
            HStack {
                Spacer()
                Button(model.nextTitle) { model.next(course) }
                    .buttonStyle(.pointing(.borderedProminent))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    func modelAnswer(_ card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(.quizModelAnswer).font(Theme.Typeface.label).foregroundStyle(accent.ink)
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

    // MARK: History

    func history(of card: QuizCard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Caption(String(localized: .quizSolveHistory))
            let past = model.past(card)
            if past.isEmpty && model.pending == nil { EmptyLine(String(localized: .quizSolveFirstTime)).font(Theme.Typeface.caption) }
            ForEach(Array(past.enumerated()), id: \.offset) { _, a in
                historyRow(a.event.verdict, overridden: a.event.overridden, detail: model.historyDetail(a))
            }
            if let pending = model.pending {
                historyRow(pending.verdict, overridden: pending.verdict != pending.original, detail: String(localized: .quizSolvePendingDetail))
            }
            status(model.quiz.history(of: card.id))
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
            Text(.quizSolveOpenSince(since.short)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
        case .resolved(_, let recheck?):
            Text(.quizSolveRecheck(recheck.short)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
        case .resolved:
            Text(.quizSolveResolved).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.success)
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
