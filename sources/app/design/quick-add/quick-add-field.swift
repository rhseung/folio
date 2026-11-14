import FolioDomain
import SwiftUI

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

extension EnvironmentValues {
    @Entry var quickAddTypedSample: String?
}
