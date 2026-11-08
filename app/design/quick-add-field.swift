import FolioDomain
import SwiftUI

/// A word the line read: the deadline, the course (in its color) or the assignment's kind and number.
struct ReadMark: TextAttribute {
    var fill: Color
    var stroke: Color?
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
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.small).path(in: pill.rect.insetBy(dx: 0, dy: -2))
                    context.fill(shape, with: .color(pill.mark.fill))
                    if let stroke = pill.mark.stroke { context.stroke(shape, with: .color(stroke), lineWidth: 1) }
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

/// One floating line that adds an assignment (`선대 HW5 금 23:59`), read as it is typed: pills behind the words it
/// read, and under the line a chip for each value it will save, which opens to correct it. Today, the toolbar's
/// popover and the assignments screen share it, so the line reads the same wherever it is typed.
struct QuickAddField: View {
    @State private var model: QuickAddModel
    @State private var fieldSize = CGSize.zero
    @State private var lineSize = CGSize.zero
    /// One and three lines of the field's font: the field's least and most height.
    @State private var lineHeights = (one: CGFloat(0), three: CGFloat(0))
    @Environment(\.quickAddTypedSample) private var typedSample

    init(workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil) {
        _model = State(initialValue: QuickAddModel(workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse))
    }

    private let font = Theme.Typeface.bodyLarge
    /// The + gets a fixed slot so the chips can start under the typed words by padding alone.
    private let plusWidth: CGFloat = 16

    var body: some View {
        let parsed = model.parsed
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary).frame(width: plusWidth)
                // Wraps instead of running sideways, so every word it read keeps its pill in sight; past three lines
                // it scrolls, and the pills step aside since they would sit under other words.
                TextField(String(localized: .quickAddPrompt), text: $model.text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(font)
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
                        .fixedSize()
                        .hidden()
                    }
                    .onSubmit { if let parsed { model.add(parsed) } }
                if let parsed {
                    Button(.quickAddAdd) { model.add(parsed) }
                        .buttonStyle(.pointing(.glassProminent))
                        .disabled(!model.canAdd(parsed))
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: 44)
            .floatingGlass()
            let chips = model.chips
            if !chips.isEmpty {
                FlowLayout(spacing: Theme.Space.s, centered: true) {
                    ForEach(chips, id: \.self) { chip in QuickAddChip(model: model, chip: chip) }
                }
                .padding(.leading, Theme.Inset.panel + plusWidth + Theme.Space.m)
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
        }
    }

    /// The line laid out again under the field, invisible, so `ReadMarkRenderer` can draw a pill behind each word read.
    private func marks(_ parsed: QuickAdd?) -> some View {
        let text = model.text
        var ranges: [(Range<String.Index>, ReadMark)] = []
        if let parsed {
            ranges += parsed.dueRanges.map { ($0, ReadMark(fill: Theme.Palette.highlightFill)) }
            if let id = parsed.courseId {
                ranges += parsed.courseRanges.map { ($0, ReadMark(fill: model.accent(id).tint)) }
            }
            if let r = parsed.kindRange { ranges.append((r, ReadMark(fill: .clear, stroke: Theme.Palette.lineStrong))) }
        }
        var mirror = Text("")
        var at = text.startIndex
        for (r, mark) in ranges.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) where r.lowerBound >= at {
            mirror = mirror + Text(Self.breakable(text[at..<r.lowerBound])) + Text(Self.breakable(text[r])).customAttribute(mark)
            at = r.upperBound
        }
        mirror = mirror + Text(Self.breakable(text[at...]))
        return mirror.font(font).textRenderer(ReadMarkRenderer())
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

private extension Character {
    var isHangul: Bool { unicodeScalars.first.map { (0xAC00...0xD7A3).contains($0.value) } ?? false }
}

/// One value the line will save, which opens to change it: the course from a list, the deadline from a calendar, the
/// repeat, the kind and number. Each is a button or menu, so a tap opens it as a click does.
struct QuickAddChip: View {
    let model: QuickAddModel
    let chip: QuickAddModel.Chip
    @State private var pickingDue = false

    var body: some View {
        Group {
            switch chip {
            case let .course(id): courseChip(id)
            case let .due(date): dueChip(date)
            case .weekly: weeklyChip
            case let .folder(name): folderChip(name)
            }
        }
        #if DEBUG && os(macOS)
        .task {
            guard case .due = chip, SnapshotDriver.shared.quickAddDueOpen else { return }
            try? await Task.sleep(for: .seconds(0.6))
            pickingDue = true
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
                label(fill: accent.tint) {
                    CourseMark(model.workspace, id, inline: true)
                    Text(title).foregroundStyle(accent.ink)
                }
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
            label(fill: Theme.Palette.fill) {
                Image(systemName: "clock").foregroundStyle(Theme.Palette.textSecondary)
                if let date, let parsed = model.parsed, let text = model.due(parsed) {
                    Text(text).foregroundStyle(Theme.Palette.text)
                    if let left = model.left(date) {
                        Text(left.text).foregroundStyle(left.overdue ? Theme.Palette.danger : Theme.Palette.textSecondary)
                    }
                } else {
                    Text(.quickAddAddDue).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .monospacedDigit()
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $pickingDue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                DatePanel(date: Binding(get: { date ?? model.newDue }, set: { model.pickDue($0) }))
                Divider()
                Toggle(String(localized: .quickAddRepeatWeekly), isOn: Binding(
                    get: { model.parsed?.repeats == .weekly },
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
        }
    }

    private var weeklyChip: some View {
        Menu {
            Button { model.pickRepeats(.weekly) } label: { Label(String(localized: .quickAddWeekly), systemImage: "checkmark") }
            Button(.quickAddNoRepeat) { model.pickRepeats(nil) }
        } label: {
            label(fill: Theme.Palette.fill) {
                Image(systemName: "repeat").foregroundStyle(Theme.Palette.textSecondary)
                Text(.quickAddWeekly).foregroundStyle(Theme.Palette.text)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    private func folderChip(_ name: String) -> some View {
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
            label(fill: Theme.Palette.fill) {
                Image(systemName: "folder").foregroundStyle(Theme.Palette.textSecondary)
                Text(verbatim: name).foregroundStyle(Theme.Palette.text)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    private func label<Content: View>(fill: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.tight) { content() }
            .font(Theme.Typeface.caption)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.m)
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
