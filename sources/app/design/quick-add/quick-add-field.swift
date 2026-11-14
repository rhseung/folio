import FolioDomain
import SwiftUI

// Mac의 text view, iPad의 field와 그 mirror가 이 값을 함께 써야 알약이 글자 자리에 놓인다.
enum QuickAddLine {
    static let spacing: CGFloat = 6
    static let overhang: CGFloat = 1
}

struct ReadMark: TextAttribute {
    var fill: Color
}

struct ReadMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // 한글과 숫자는 다른 글꼴에서 오므로 한 구절이 run 여러 개에 걸친다. 이 run들을 알약 하나로 합친다.
            var pill: (rect: CGRect, mark: ReadMark)?
            func flush() {
                if let pill {
                    // 글리프보다 넓히지 않는다. 읽은 낱말과 다음 낱말 사이의 공백 하나가 자리의 전부라서, 그 안으로
                    // 들어간 알약이 이웃 낱말이나 다음 알약에 닿았다. 간격 자체를 넓히려면 필드의 글에 kerning을 줘야
                    // 하는데, 그러면 한글 조합 중에 글이 다시 쓰인다.
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.small).path(
                        in: pill.rect.insetBy(dx: 0, dy: -QuickAddLine.overhang))
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

struct QuickAddField: View {
    @State private var model: QuickAddModel
    @State private var fieldSize = CGSize.zero
    @State private var lineSize = CGSize.zero
    @State private var lineHeights = (one: CGFloat(0), three: CGFloat(0))
    @Environment(\.quickAddTypedSample) private var typedSample

    private let focusOnAppear: Bool
    private let floating: Bool

    init(
        workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil, showsEmptyChips: Bool = false,
        focusOnAppear: Bool = false, floating: Bool = false
    ) {
        _model = State(
            initialValue: QuickAddModel(
                workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse,
                showsEmptyChips: showsEmptyChips))
        self.focusOnAppear = focusOnAppear
        self.floating = floating
    }

    private let font = Theme.Typeface.bodyLarge
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
                #if os(macOS)
                QuickAddTextView(
                    text: $model.text, prompt: String(localized: .quickAddPrompt), marks: textMarks(parsed),
                    focusOnAppear: focusOnAppear
                ) { model.submit() }
                .frame(maxWidth: .infinity, alignment: .leading)
                #else
                TextField(String(localized: .quickAddPrompt), text: $model.text, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(font)
                    .lineSpacing(QuickAddLine.spacing)
                    // 높이는 mirror에서 잰다. 편집 중인 필드는 코드에서 줄을 바꾸면(칩에서 고르면) 커진 것을 SwiftUI에
                    // 알리지 않아, 세 줄이 보이는데도 한 줄 높이를 유지한다.
                    .frame(height: lineHeights.one == 0 ? nil : min(max(lineSize.height, lineHeights.one), lineHeights.three))
                    // 필드의 글에 스타일을 주지 않고 필드 뒤에 표시를 그린다. 입력 중에 글을 다시 쓰면 한글 조합이
                    // 깨지고 글자가 사라진다.
                    .background(alignment: .topLeading) {
                        marks(parsed)
                            .frame(width: fieldSize.width, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGSize.self) {
                                $0.size
                            } action: {
                                lineSize = $0
                            }
                            .opacity(lineSize.height <= lineHeights.three + 1 ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: {
                        fieldSize = $0
                    }
                    .background {
                        VStack {
                            Text(verbatim: "A").onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                lineHeights.one = $0
                            }
                            Text(verbatim: "A\nA\nA").onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                lineHeights.three = $0
                            }
                        }
                        .font(font)
                        .lineSpacing(QuickAddLine.spacing)
                        .fixedSize()
                        .hidden()
                    }
                    .submitLabel(.done)
                    .onSubmit { model.submit() }
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

    private func fill(_ field: QuickAdd.Span.Field, _ parsed: QuickAdd) -> Color? {
        switch field {
        case .due: Theme.Palette.readDue
        case .course: parsed.courseId.map { model.accent($0).read }
        case .kind: Theme.Palette.readFolder
        }
    }

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

    // 필드는 한글 줄을 아무 두 글자 사이에서나 끊지만 `Text`는 한글 낱말을 통째로 둔다. 그러면 줄바꿈된 줄에서 알약이
    // 한 낱말씩 어긋나므로, 한글 글자 사이에 zero-width space를 넣어 mirror가 필드처럼 끊게 한다.
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

struct QuickAddChip: View {
    static let inset = Theme.Space.m
    let model: QuickAddModel
    let chip: QuickAddModel.Chip
    @State private var pickingDue = false
    @State private var pickingRepeat = false
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
                Button {
                    model.pickCourse(c.id)
                } label: {
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
        Button {
            pickingDue = true
        } label: {
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
                Toggle(
                    String(localized: .quickAddRepeatToggle),
                    isOn: Binding(
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
            // popover는 열릴 때의 높이를 제안하므로, 첫 날짜를 골라 아래에 지우기 버튼이 생기면 높이가 모자란다.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dueLabel(_ date: Date?) -> some View {
        label(fill: Theme.Palette.readDue) {
            Image(systemName: "clock")
            if let date, let parsed = model.parsed, let text = model.due(parsed) {
                Text(text)
                if let left = model.left(date) {
                    Text(left.text).foregroundStyle(
                        left.overdue ? Theme.Palette.danger : Theme.Palette.readDueInk.opacity(Theme.Opacity.secondaryInk))
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
            RepeatMenuItems(
                selection: repeats, custom: repeats.map { !AssignmentRepeat.presets.contains($0) } ?? false,
                pick: { model.pickRepeats($0) },
                customize: {
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
                RepeatRuleRows(
                    rule: Binding(
                        get: { rule },
                        set: {
                            rule = $0; model.pickRepeats($0)
                        }), dueWeekday: model.dueWeekday, last: true)
            }
            .padding(Theme.Space.l)
            .frame(width: 360)
            // popover는 마지막에 받은 높이를 제안한다. 개월로 바꿨다가 주로 돌아오면 요일 줄이 더 낮은 높이에 눌려 행이
            // 카드 가장자리 밖으로 넘쳤다.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folderChip(_ name: String?) -> some View {
        let current = model.kind
        return Menu {
            Section(String(localized: .quickAddKind)) {
                ForEach(AssignmentKind.allCases, id: \.self) { kind in
                    Button {
                        model.renumber(kind: kind, number: current?.number ?? 1)
                    } label: {
                        if kind == current?.kind { Label(kind.rawValue, systemImage: "checkmark") } else { Text(kind.rawValue) }
                    }
                }
            }
            Menu(String(localized: .quickAddNumber)) {
                ForEach(1...20, id: \.self) { n in
                    Button {
                        model.renumber(kind: current?.kind ?? .homework, number: n)
                    } label: {
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
        .padding(.vertical, Theme.Space.s)
        .contentShape(.rect)
            #endif
    }
}

extension EnvironmentValues {
    @Entry var quickAddTypedSample: String?
}
