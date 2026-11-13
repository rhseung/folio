import FolioDomain
import SwiftUI

/// How the quick add line sets its rows, shared by the Mac's text view and the iPad's field and its mirror, so the
/// pills land where the words are.
enum QuickAddLine {
    /// Between wrapped rows: room for a pill to reach `overhang` above and below its row and still leave 4pt to the
    /// pill on the next row. At the font's own spacing the two pills touched.
    static let spacing: CGFloat = 6
    static let overhang: CGFloat = 1
}

struct ReadMark: TextAttribute {
    var fill: Color
}

/// Draws only rounded pills behind runs marked `ReadMark`; the glyphs come from the field on top.
struct ReadMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // Korean and digits come from different fonts, so one phrase spans several runs; they join into one pill.
            var pill: (rect: CGRect, mark: ReadMark)?
            func flush() {
                if let pill {
                    // No wider than the glyphs: the one space between a read word and the next is all the room
                    // there is, and a pill reaching into it touched the neighbor (or the next pill). Widening the gap
                    // itself would mean kerning the field's own text, which rewrites it under Korean composition.
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.small).path(in: pill.rect.insetBy(dx: 0, dy: -QuickAddLine.overhang))
                    context.fill(shape, with: .color(pill.mark.fill))
                }
                pill = nil
            }
            for run in line {
                if let mark = run[ReadMark.self] {
                    let rect = run.typographicBounds.rect
                    if let current = pill, current.mark == mark {
                        pill = (current.rect.union(rect), mark)
                    } else {
                        flush()
                        pill = (rect, mark)
                    }
                } else {
                    flush()
                }
            }
            flush()
        }
    }
}

/// Today, the toolbar's popover and the assignments screen share it, so the line reads the same wherever it is typed.
struct QuickAddField: View {
    @State private var model: QuickAddModel
    @State private var fieldSize = CGSize.zero
    @State private var lineSize = CGSize.zero
    /// One and three lines of the field's font: the field's least and most height.
    @State private var lineHeights = (one: CGFloat(0), three: CGFloat(0))
    @Environment(\.quickAddTypedSample) private var typedSample

    private let focusOnAppear: Bool
    /// In the toolbar's popover, a floating thing, the field is glass; on the page it is paper like the page's other
    /// fields (`Card`), since glass belongs only to the frame and what floats over it.
    private let floating: Bool

    init(workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil, showsEmptyChips: Bool = false,
         focusOnAppear: Bool = false, floating: Bool = false) {
        _model = State(initialValue: QuickAddModel(workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse,
                                                   showsEmptyChips: showsEmptyChips))
        self.focusOnAppear = focusOnAppear
        self.floating = floating
    }

    private let font = Theme.Typeface.bodyLarge
    /// Inside the field, as inside a card's padded field (the memo): at less, a pill on the first word sat against the
    /// field's wall. The Mac's text view keeps `QuickAddTextView.room` before the first letter for a pill there, so
    /// the letters start at the same inset on both.
    private let inset = Theme.Space.l
    #if os(macOS)
    private let leading = Theme.Space.l - QuickAddTextView.room
    #else
    private let leading = Theme.Space.l
    #endif

    var body: some View {
        let parsed = model.parsed
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Group {
                // Wraps instead of running sideways, so every word it read keeps its pill in sight; past three lines
                // it scrolls.
                #if os(macOS)
                QuickAddTextView(text: $model.text, prompt: String(localized: .quickAddPrompt), marks: textMarks(parsed),
                                 focusOnAppear: focusOnAppear) { model.submit() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                #else
                TextField(String(localized: .quickAddPrompt), text: $model.text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(font)
                    .lineSpacing(QuickAddLine.spacing)
                    // The height comes from the mirror: a field being edited does not tell SwiftUI it grew when the
                    // line is set from code (a chip's pick), and keeps one line while three show.
                    .frame(height: lineHeights.one == 0 ? nil : min(max(lineSize.height, lineHeights.one), lineHeights.three))
                    // The marks are drawn behind the field instead of styling its text: rewriting the text while
                    // typing breaks Korean composition and eats characters.
                    .background(alignment: .topLeading) {
                        marks(parsed)
                            .frame(width: fieldSize.width, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { lineSize = $0 }
                            .opacity(lineSize.height <= lineHeights.three + 1 ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { fieldSize = $0 }
                    .background {
                        VStack {
                            Text(verbatim: "A").onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeights.one = $0 }
                            Text(verbatim: "A\nA\nA").onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeights.three = $0 }
                        }
                        .font(font)
                        .lineSpacing(QuickAddLine.spacing)
                        .fixedSize()
                        .hidden()
                    }
                    // The keyboard's Return is the touch path to add.
                    .submitLabel(.done)
                    .onSubmit { model.submit() }
                    // A field that wraps takes Return as a new line rather than a submit: a line ending in one is
                    // the Return key, and lines pasted in join into the one line.
                    .onChange(of: model.text) { _, text in
                        guard text.contains(where: \.isNewline) else { return }
                        let returned = text.last?.isNewline == true
                        model.text = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                        if returned { model.submit() }
                    }
                #endif
            }
            .padding(.leading, leading)
            .padding(.trailing, inset)
            .padding(.vertical, inset)
            .frame(minHeight: 52)
            .modifier(QuickAddSurface(floating: floating))
            let chips = model.chips
            if !chips.isEmpty {
                // Each chip's icon under the field's first letter, and across the field's width: indented further
                // the row read as cut in and wrapped a chip early.
                FlowLayout(spacing: Theme.Space.s, centered: true) {
                    ForEach(chips, id: \.kind) { chip in QuickAddChip(model: model, chip: chip) }
                }
                .padding(.leading, inset - QuickAddChip.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            var sample = typedSample
            #if DEBUG && os(macOS)
            sample = sample ?? SnapshotDriver.shared.quickAddText
            #endif
            guard let sample, model.text.isEmpty else { return }
            // Word by word, as it is typed.
            try? await Task.sleep(for: .seconds(0.3))
            for word in sample.split(separator: " ", omittingEmptySubsequences: false) {
                model.text += (model.text.isEmpty ? "" : " ") + word
                try? await Task.sleep(for: .seconds(0.03))
            }
            #if DEBUG && os(macOS)
            if let pick = SnapshotDriver.shared.quickAddPick {
                try? await Task.sleep(for: .seconds(1))
                model.pickCourse(pick)
            }
            #endif
        }
    }

    #if os(macOS)
    private func textMarks(_ parsed: QuickAdd?) -> [QuickAddMark] {
        guard let parsed else { return [] }
        let text = model.text
        func range(_ r: Range<String.Index>) -> NSRange? {
            r.upperBound <= text.endIndex ? NSRange(r, in: text) : nil
        }
        return parsed.spans.compactMap { span in
            guard let r = range(span.range), let color = fill(span.field, parsed) else { return nil }
            return QuickAddMark(range: r, fill: color)
        }
    }
    #endif

    /// A word's pill color. The course's comes from what will be saved, not from the word: a course picked on the chip
    /// recolors the word, and with the course cleared the word has no pill.
    private func fill(_ field: QuickAdd.Span.Field, _ parsed: QuickAdd) -> Color? {
        switch field {
        case .due: Theme.Palette.readDue
        case .course: parsed.courseId.map { model.accent($0).read }
        case .kind: Theme.Palette.readFolder
        }
    }

    /// The line laid out again under the field, invisible, so `ReadMarkRenderer` can draw a pill behind each word read.
    private func marks(_ parsed: QuickAdd?) -> some View {
        let text = model.text
        var ranges: [(Range<String.Index>, ReadMark)] = []
        if let parsed {
            for span in parsed.spans {
                if let color = fill(span.field, parsed) { ranges.append((span.range, ReadMark(fill: color))) }
            }
        }
        var mirror = Text("")
        var at = text.startIndex
        for (r, mark) in ranges.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) where r.lowerBound >= at {
            mirror = mirror + Text(Self.breakable(text[at..<r.lowerBound])) + Text(Self.breakable(text[r])).customAttribute(mark)
            at = r.upperBound
        }
        mirror = mirror + Text(Self.breakable(text[at...]))
        return mirror.font(font).lineSpacing(QuickAddLine.spacing).textRenderer(ReadMarkRenderer())
    }

    /// The field breaks a Korean line between any two letters while `Text` keeps Korean words whole, so on a wrapped
    /// line the pills would land a word off. A zero-width space between Hangul letters lets the mirror break as the
    /// field does.
    static func breakable(_ s: Substring) -> String {
        var out = ""
        var previous: Character?
        for c in s {
            if let p = previous, p.isHangul, c.isHangul { out.append("\u{200B}") }
            out.append(c)
            previous = c
        }
        return out
    }
}

private struct QuickAddSurface: ViewModifier {
    let floating: Bool

    func body(content: Content) -> some View {
        if floating {
            content.floatingGlass()
        } else {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
            content
                .surface(Theme.Palette.card, in: shape)
                .overlay(shape.strokeBorder(Theme.Palette.lineSoft))
        }
    }
}

private extension Character {
    var isHangul: Bool { unicodeScalars.first.map { (0xAC00...0xD7A3).contains($0.value) } ?? false }
}

/// Each chip is a button or menu, so a tap opens it as a click does.
struct QuickAddChip: View {
    static let inset = Theme.Space.m
    let model: QuickAddModel
    let chip: QuickAddModel.Chip
    @State private var pickingDue = false
    @State private var pickingRepeat = false
    /// What the rule popover edits; each change is written into the line, which may read it slightly differently.
    @State private var rule = AssignmentRepeat.weekly

    var body: some View {
        Group {
            switch chip {
            case let .course(id): courseChip(id)
            case let .due(date): dueChip(date)
            case let .repeats(repeats): repeatsChip(repeats)
            case let .folder(name): folderChip(name)
            }
        }
        #if DEBUG && os(macOS)
        .task {
            switch chip {
            case .due where SnapshotDriver.shared.quickAddDueOpen:
                try? await Task.sleep(for: .seconds(0.6))
                pickingDue = true
            case let .repeats(repeats?) where SnapshotDriver.shared.quickAddRepeatOpen:
                try? await Task.sleep(for: .seconds(0.6))
                rule = repeats
                pickingRepeat = true
            default: break
            }
        }
        #endif
    }

    private func courseChip(_ id: UUID?) -> some View {
        Menu {
            ForEach(model.courses, id: \.id) { c in
                Button { model.pickCourse(c.id) } label: {
                    if c.id == id { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                }
            }
        } label: {
            if let id, let title = model.courseTitle(id) {
                let accent = model.accent(id)
                label(fill: accent.read) {
                    CourseMark(model.workspace, id, inline: true)
                    Text(title).foregroundStyle(accent.ink)
                }
            } else if model.isDimmed(chip) {
                dimmed("book.closed", .quickAddChipCourse)
            } else {
                label(fill: Theme.Palette.dangerFill) {
                    Image(systemName: "exclamationmark.circle")
                    Text(.quickAddPickCourse)
                }
                .foregroundStyle(Theme.Palette.danger)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    private func dueChip(_ date: Date?) -> some View {
        Button { pickingDue = true } label: {
            if model.isDimmed(chip) {
                dimmed("clock", .quickAddChipDue)
            } else {
                dueLabel(date)
            }
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $pickingDue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                DatePanel(date: Binding(get: { date ?? model.newDue }, set: { model.pickDue($0) }))
                Divider()
                Toggle(String(localized: .quickAddRepeatToggle), isOn: Binding(
                    get: { model.parsed?.repeats != nil },
                    set: { on in
                        if on, model.parsed?.due == nil { model.pickDue(model.newDue) }
                        model.pickRepeats(on ? .weekly : nil)
                    }))
                if date != nil {
                    Button(String(localized: .quickAddClearDue), role: .destructive) {
                        model.pickDue(nil)
                        pickingDue = false
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(Theme.Space.l)
            .frame(width: 280)
            // A popover proposes the height it opened with: picking a first date adds the clear button under it.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dueLabel(_ date: Date?) -> some View {
        label(fill: Theme.Palette.readDue) {
            Image(systemName: "clock")
            if let date, let parsed = model.parsed, let text = model.due(parsed) {
                Text(text)
                if let left = model.left(date) {
                    Text(left.text).foregroundStyle(left.overdue ? Theme.Palette.danger : Theme.Palette.readDueInk.opacity(Theme.Opacity.secondaryInk))
                }
            } else {
                Text(.quickAddAddDue)
            }
        }
        .foregroundStyle(Theme.Palette.readDueInk)
        .monospacedDigit()
    }

    private func repeatsChip(_ repeats: AssignmentRepeat?) -> some View {
        Menu {
            RepeatMenuItems(selection: repeats, custom: repeats.map { !AssignmentRepeat.presets.contains($0) } ?? false,
                            pick: { model.pickRepeats($0) }, customize: {
                                rule = repeats ?? .weekly
                                if repeats == nil { model.pickRepeats(rule) }
                                pickingRepeat = true
                            })
        } label: {
            if model.isDimmed(chip) {
                dimmed("repeat", .quickAddChipRepeat)
            } else {
                label(fill: Theme.Palette.readDue) {
                    Image(systemName: "repeat")
                    Text(repeats?.label ?? "")
                }
                .foregroundStyle(Theme.Palette.readDueInk)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
        .popover(isPresented: $pickingRepeat, arrowEdge: .bottom) {
            Card {
                RepeatRuleRows(rule: Binding(get: { rule }, set: { rule = $0; model.pickRepeats($0) }), dueWeekday: model.dueWeekday, last: true)
            }
            .padding(Theme.Space.l)
            .frame(width: 360)
            // A popover proposes the height it last took: switching to 개월 and back to 주 squeezed the weekday row
            // into the shorter height, and the rows spilled over the card's edges.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folderChip(_ name: String?) -> some View {
        let current = model.kind
        return Menu {
            Section(String(localized: .quickAddKind)) {
                ForEach(AssignmentKind.allCases, id: \.self) { kind in
                    Button { model.renumber(kind: kind, number: current?.number ?? 1) } label: {
                        if kind == current?.kind { Label(kind.rawValue, systemImage: "checkmark") } else { Text(kind.rawValue) }
                    }
                }
            }
            Menu(String(localized: .quickAddNumber)) {
                ForEach(1...20, id: \.self) { n in
                    Button { model.renumber(kind: current?.kind ?? .homework, number: n) } label: {
                        if n == current?.number { Label(String(n), systemImage: "checkmark") } else { Text(String(n)) }
                    }
                }
            }
        } label: {
            if let name {
                label(fill: Theme.Palette.readFolder) {
                    Image(systemName: "folder")
                    Text(verbatim: name)
                }
                .foregroundStyle(Theme.Palette.readFolderInk)
            } else {
                dimmed("folder", .quickAddChipFolder)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    /// A chip with nothing read yet: what the line can read, in a quiet wash of the text color that reads the same on
    /// the paper card and the popover's glass. Still a button, so a value can be picked by touch.
    private func dimmed(_ icon: String, _ title: LocalizedStringResource) -> some View {
        label(fill: Theme.Palette.text.opacity(Theme.Opacity.wash)) {
            Image(systemName: icon)
            Text(title)
        }
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func label<Content: View>(fill: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.tight) { content() }
            .font(Theme.Typeface.caption)
            .lineLimit(1)
            .padding(.horizontal, Self.inset)
            .frame(height: 28)
            .background(fill, in: .capsule)
            .contentShape(.capsule)
            #if os(iOS)
            // The chip stays 28 tall, but a finger gets the 44pt the row's gap leaves around it.
            .padding(.vertical, Theme.Space.s)
            .contentShape(.rect)
            #endif
    }
}

extension EnvironmentValues {
    /// A line already typed into the field, for window snapshots of it mid-typing.
    @Entry var quickAddTypedSample: String?
}
