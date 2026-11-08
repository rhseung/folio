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

/// One floating line that adds an assignment (`선대 HW5 금 23:59`), read as it is typed: pills behind the words taken
/// as the deadline, and under the line what will be saved. Today, the toolbar's popover and the assignments screen
/// share it, so the line reads the same wherever it is typed.
struct QuickAddField: View {
    @State private var model: QuickAddModel
    @State private var fieldWidth: CGFloat = 0
    @State private var lineWidth: CGFloat = 0
    @Environment(\.quickAddTypedSample) private var typedSample

    init(workspace: Workspace, fixedCourse: UUID? = nil, defaultCourse: UUID? = nil) {
        _model = State(initialValue: QuickAddModel(workspace: workspace, fixedCourse: fixedCourse, defaultCourse: defaultCourse))
    }

    private let font = Theme.Typeface.bodyLarge
    /// The + gets a fixed slot so the summary can start under the typed words by padding alone. Aligning it by a
    /// guide instead shifted it right of the field, and a long summary then widened the whole field past its frame.
    private let plusWidth: CGFloat = 16

    var body: some View {
        let parsed = model.parsed
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary).frame(width: plusWidth)
                TextField(String(localized: .quickAddPrompt), text: $model.text)
                    .textFieldStyle(.plain)
                    .font(font)
                    // The marks are drawn behind the field instead of styling its text: rewriting the text while
                    // typing breaks Korean composition and eats characters. Past the field's width the field scrolls
                    // its text and the marks would sit under other words, so they show only while the line fits.
                    .background(alignment: .leading) {
                        marks(parsed?.dueRanges ?? [])
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
                            .opacity(lineWidth <= fieldWidth ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }
                    .onSubmit { if let parsed { model.add(parsed) } }
                if let parsed {
                    Button(.quickAddAdd) { model.add(parsed) }
                        .buttonStyle(.pointing(.glassProminent))
                        .disabled(!model.canAdd(parsed))
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .frame(height: 44)
            .floatingGlass()
            // Under the field, not inside it: beside the typed line it ran out of room and cut off the deadline.
            if parsed != nil || model.defaultCourse != nil {
                summary(parsed)
                    .padding(.leading, Theme.Inset.panel + plusWidth + Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            var sample = typedSample
            #if DEBUG && os(macOS)
            sample = sample ?? SnapshotDriver.shared.quickAddText
            #endif
            if let sample, model.text.isEmpty { model.text = sample }
        }
    }

    /// The course leads unless the field belongs to one; then the line starts at the deadline. A default course shows
    /// before anything is typed, so the line says where it will go. The title gives way first when the line is long.
    private func summary(_ parsed: QuickAdd?) -> some View {
        let leadsWithCourse = model.fixedCourse == nil
        let items = parsed.map(model.summary) ?? []
        return HStack(spacing: Theme.Space.tight) {
            if leadsWithCourse {
                Group {
                    if let id = model.course(parsed), let title = model.courseTitle(id) {
                        CourseMark(model.workspace, id, inline: true)
                        Text(title).foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Text(.quickAddNoCourse).foregroundStyle(Theme.Palette.danger)
                    }
                }
                .layoutPriority(1)
            }
            ForEach(Array(items.enumerated()), id: \.element) { i, item in
                Group {
                    if leadsWithCourse || i > 0 { Text(verbatim: "·") }
                    switch item {
                    case let .due(due): Text(due).layoutPriority(1)
                    case .weekly: Label(.quickAddWeekly, systemImage: "repeat").layoutPriority(1)
                    case let .title(title): Text(title).truncationMode(.tail)
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

extension EnvironmentValues {
    /// A line already typed into the field, for window snapshots of it mid-typing.
    @Entry var quickAddTypedSample: String?
}
