import FolioDomain
import SwiftUI

/// Muted label above a value.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary)
    }
}

/// Rounded colored square with a symbol or a short text, used to mark rows in sidebars and lists.
struct IconTile: View {
    let color: Color
    var symbol: String?
    var text: String?
    var size: CGFloat = Theme.Size.tile

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile * size / Theme.Size.tile)
            .fill(LinearGradient(colors: [color.opacity(0.78), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                if let symbol {
                    // Symbols differ in how much of their box they fill; a smaller size keeps dense ones (charts) from looking oversized.
                    Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold))
                } else if let text {
                    Text(text).font(.system(size: size * 0.5, weight: .bold))
                }
            }
            .foregroundStyle(Theme.Palette.onFill)
    }
}

/// A row of figures sharing one card, separated by hairlines.
struct StatStrip: View {
    struct Item: Identifiable {
        var id: String { title }
        let title: String
        let value: String
        var detail: String?
        var tone: Tone = .plain
        /// A grade: hidden while grades are locked, the title staying.
        var sensitive = false
        var action: (() -> Void)?
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Theme.Palette.lineSoft.frame(width: 1) }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Caption(item.title)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(item.value).font(Theme.Typeface.figureSmall).foregroundStyle(item.tone.foreground).lineLimit(1).rolling(item.value)
                        if let detail = item.detail {
                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                    }
                    .sensitive(item.sensitive ? .inline : nil)
                }
                .padding(Theme.Inset.stat)
                // Top-aligned at full height, so an item without a detail line doesn't sink below its neighbors.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opens(item.action)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }
}

/// Meaning carried by color in badges and figures.
enum Tone {
    case plain, accent, warning, danger, success

    @MainActor var foreground: Color {
        switch self {
        case .plain, .accent: Theme.Palette.text
        case .warning: Theme.Palette.warning
        case .danger: Theme.Palette.danger
        case .success: Theme.Palette.success
        }
    }

    @MainActor var fill: Color {
        switch self {
        case .plain, .accent, .success: Theme.Palette.fill
        case .warning: Theme.Palette.warningFill
        case .danger: Theme.Palette.dangerFill
        }
    }
}

/// Small rounded label. `.accent` takes the course color from the environment.
struct Chip: View {
    @Environment(\.accent) private var accent
    let text: String
    var tone: Tone = .plain

    init(_ text: String, tone: Tone = .plain) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(Theme.Typeface.caption.weight(tone == .plain ? .regular : .semibold))
            .foregroundStyle(tone == .accent ? accent.ink : tone == .plain ? Theme.Palette.textSecondary : tone.foreground)
            // A squeezed row wrapped the label a letter per line; the text beside the chip gives way instead.
            .lineLimit(1)
            .fixedSize()
            .padding(Theme.Inset.tag)
            .background(tone == .accent ? accent.tint : tone.fill, in: .capsule)
    }
}

/// A person's initial on a color fixed by their id, so a long list of names reads at a glance.
struct Avatar: View {
    let name: String
    let id: UUID
    var size: CGFloat = 26

    var body: some View {
        let accent = CourseAccent.presets[Int(id.uuid.0) % CourseAccent.presets.count].accent
        Circle().fill(accent.color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(accent.ink)
            }
    }
}

/// A course where it stands for itself (sidebar, course column, breadcrumb): its symbol in its color, the book unless
/// one was picked. Rows that only tag an item with its course keep the plain dot.
struct CourseMark: View {
    let icon: String?
    let color: Color
    var font: Font = Theme.Glyph.line
    var filled = false
    // Within a line of text the symbol takes the text's size; the icon column's 22pt square would gap the line.
    var inline = false

    static let defaultIcon = "book.closed"

    var body: some View {
        if inline {
            Image(systemName: icon ?? Self.defaultIcon).foregroundStyle(color)
        } else {
            LineIcon(symbol: icon ?? Self.defaultIcon, font: font, filled: filled).foregroundStyle(color)
        }
    }
}

extension CourseMark {
    init(_ workspace: Workspace, _ id: UUID, inline: Bool = false) {
        self.init(icon: workspace.course(id)?.file.course.icon, color: workspace.accent(id).color, inline: inline)
    }
}

struct CourseDot: View {
    let color: Color
    var size: CGFloat = Theme.Size.dot
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// Thin progress bar in the course accent.
struct Meter: View {
    @Environment(\.accent) private var accent
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        Capsule().fill(accent.tint)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(accent.color).frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: height)
    }
}

/// Muted line used where a list has nothing to show.
struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func rolling(_ value: String) -> some View {
        contentTransition(.numericText()).animation(.snappy(duration: 0.35), value: value)
    }
}

/// A round check in the course accent.
struct CheckCircle: View {
    @Environment(\.accent) private var accent
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(Theme.Glyph.check)
                .foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
        }
        .buttonStyle(.pointing(.plain))
    }
}

/// A caption over a large number that rolls when it changes.
struct Figure: View {
    let title: String
    let value: String
    var tint: Color = Theme.Palette.text
    var font: Font = Theme.Typeface.figure

    init(_ title: String, _ value: String, tint: Color = Theme.Palette.text, font: Font = Theme.Typeface.figure) {
        self.title = title
        self.value = value
        self.tint = tint
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Caption(title)
            Text(value).font(font).foregroundStyle(tint).rolling(value).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

extension Double {
    /// Scores and percentages read to one decimal: `87.5`.
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
}
