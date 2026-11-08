import FolioDomain
import SwiftUI

struct DateMark: TextAttribute {}

/// Draws only rounded pills behind runs marked `DateMark`; the glyphs come from the field on top.
struct DateMarkRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            // Korean and digits come from different fonts, so one phrase spans several runs; they join into one pill.
            var pill: CGRect?
            func flush() {
                if let rect = pill?.insetBy(dx: -4, dy: -2) {
                    context.fill(RoundedRectangle(cornerRadius: Theme.Radius.small).path(in: rect), with: .color(Theme.Palette.highlightFill))
                }
                pill = nil
            }
            for run in line {
                if run[DateMark.self] != nil {
                    let rect = run.typographicBounds.rect
                    pill = pill.map { $0.union(rect) } ?? rect
                } else {
                    flush()
                }
            }
            flush()
        }
    }
}

enum QuickAddSurface {
    /// A floating field of its own, as on Today and in the toolbar's popover.
    case glass
    /// Inside a card row of a sheet: glass belongs only to what floats.
    case row
}

/// One line that adds an assignment (`선대 HW5 금 23:59`), read as it is typed: pills behind the words taken as the
/// deadline, and under the line what will be saved. The same field everywhere; only its surface follows where it sits.
struct QuickAddField<Trailing: View>: View {
    @State private var model: QuickAddModel
    @Environment(\.quickAddTypedSample) private var typedSample
    let prompt: String
    let surface: QuickAddSurface
    let added: ((QuickAdd) -> Void)?
    let trailing: Trailing

    init(workspace: Workspace, fixedCourse: UUID? = nil, prompt: String? = nil, surface: QuickAddSurface = .glass,
         added: ((QuickAdd) -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        _model = State(initialValue: QuickAddModel(workspace: workspace, fixedCourse: fixedCourse))
        self.prompt = prompt ?? String(localized: .quickAddPrompt)
        self.surface = surface
        self.added = added
        self.trailing = trailing()
    }

    private var font: Font { surface == .glass ? Theme.Typeface.bodyLarge : Theme.Typeface.body }

    var body: some View {
        let parsed = model.parsed
        VStack(alignment: .typedLine, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary)
                TextField(prompt, text: $model.text)
                    .textFieldStyle(.plain)
                    .font(font)
                    // The marks are drawn behind the field instead of styling its text: rewriting the text while
                    // typing breaks Korean composition and eats characters.
                    .background(alignment: .leading) { marks(parsed?.dueRanges ?? []).allowsHitTesting(false) }
                    .alignmentGuide(.typedLine) { $0[.leading] }
                    .onSubmit { if let parsed { add(parsed) } }
                if let parsed { saveButton(parsed) }
                trailing
            }
            .modifier(FieldSurface(surface: surface))
            // Under the field, not inside it: beside the typed line it ran out of room and cut off the deadline.
            if let parsed { summary(parsed).alignmentGuide(.typedLine) { $0[.leading] } }
        }
        .onAppear { if let typedSample, model.text.isEmpty { model.text = typedSample } }
    }

    @ViewBuilder private func saveButton(_ parsed: QuickAdd) -> some View {
        let button = Button(.quickAddAdd) { add(parsed) }.disabled(!model.canAdd(parsed))
        switch surface {
        case .glass: button.buttonStyle(.pointing(.glassProminent))
        case .row: button.buttonStyle(.ghost)
        }
    }

    private func add(_ parsed: QuickAdd) {
        if model.add(parsed) { added?(parsed) }
    }

    /// The course leads unless the field belongs to one; then the line starts at the deadline.
    private func summary(_ parsed: QuickAdd) -> some View {
        let leadsWithCourse = model.fixedCourse == nil
        return HStack(spacing: Theme.Space.tight) {
            if leadsWithCourse {
                if let id = parsed.courseId, let title = model.courseTitle(parsed) {
                    CourseMark(model.workspace, id, inline: true)
                    Text(title).foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(.quickAddNoCourse).foregroundStyle(Theme.Palette.danger)
                }
            }
            ForEach(Array(model.summary(parsed).enumerated()), id: \.element) { i, item in
                Group {
                    if leadsWithCourse || i > 0 { Text(verbatim: "·") }
                    switch item {
                    case let .due(due): Text(due)
                    case .weekly: Label(.quickAddWeekly, systemImage: "repeat")
                    case let .title(title): Text(title)
                    }
                }
                .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .font(Theme.Typeface.caption).lineLimit(1)
    }

    /// The line laid out again under the field, invisible, so `DateMarkRenderer` can draw a pill behind the deadline words.
    private func marks(_ ranges: [Range<String.Index>]) -> some View {
        let text = model.text
        var mirror = Text("")
        var at = text.startIndex
        for r in ranges {
            mirror = mirror + Text(text[at..<r.lowerBound]) + Text(text[r]).customAttribute(DateMark())
            at = r.upperBound
        }
        mirror = mirror + Text(text[at...])
        return mirror.font(font).lineLimit(1).fixedSize().textRenderer(DateMarkRenderer())
    }
}

extension QuickAddField where Trailing == EmptyView {
    init(workspace: Workspace, fixedCourse: UUID? = nil, prompt: String? = nil, surface: QuickAddSurface = .glass,
         added: ((QuickAdd) -> Void)? = nil) {
        self.init(workspace: workspace, fixedCourse: fixedCourse, prompt: prompt, surface: surface, added: added) { EmptyView() }
    }
}

private struct FieldSurface: ViewModifier {
    let surface: QuickAddSurface

    func body(content: Content) -> some View {
        switch surface {
        case .glass: content.padding(.horizontal, Theme.Inset.panel).frame(height: 44).floatingGlass()
        case .row: content
        }
    }
}

private extension HorizontalAlignment {
    /// Where the typed line starts, so the summary under it lines up with the words rather than the + before them.
    enum TypedLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] }
    }

    static let typedLine = HorizontalAlignment(TypedLine.self)
}

extension EnvironmentValues {
    /// A line already typed into the field, for window snapshots of it mid-typing.
    @Entry var quickAddTypedSample: String?
}
