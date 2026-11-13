import FolioDomain
import SwiftUI

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
    }
}

struct StatStrip: View {
    struct Item: Identifiable {
        var id: String { title }
        let title: String
        let value: String
        var detail: String?
        var tone: Tone = .plain
        var sensitive = false
        var action: (() -> Void)?
    }

    let items: [Item]

    static let itemRoom: CGFloat = 128

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(items).frame(idealWidth: CGFloat(items.count) * Self.itemRoom)
            VStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    if start > 0 { Theme.Palette.lineSoft.frame(height: 1) }
                    row(Array(items[start..<min(start + 2, items.count)]))
                }
            }
        }
        .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }

    func row(_ items: [Item]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Theme.Palette.lineSoft.frame(width: 1) }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Caption(item.title)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(item.value).font(Theme.Typeface.figureSmall).foregroundStyle(item.tone.foreground).lineLimit(1).rolling(
                            item.value)
                        if let detail = item.detail {
                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                    }
                    .sensitive(item.sensitive ? .inline : nil)
                }
                .padding(Theme.Inset.stat)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opens(item.action)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum Tone {
    case plain, accent, warning, danger, success, info

    @MainActor var foreground: Color {
        switch self {
        case .plain, .accent: Theme.Palette.text
        case .warning: Theme.Palette.warning
        case .danger: Theme.Palette.danger
        case .success: Theme.Palette.success
        case .info: Theme.Palette.info
        }
    }

    @MainActor var fill: Color {
        switch self {
        case .plain, .accent: Theme.Palette.fill
        case .success: Theme.Palette.success.opacity(Theme.Opacity.tint)
        case .warning: Theme.Palette.warningFill
        case .danger: Theme.Palette.dangerFill
        case .info: Theme.Palette.infoFill
        }
    }
}

struct Chip: View {
    @Environment(\.accent) private var accent
    let text: String
    var tone: Tone = .plain
    var solid = false

    init(_ text: String, tone: Tone = .plain, solid: Bool = false) {
        self.text = text
        self.tone = tone
        self.solid = solid
    }

    var body: some View {
        Text(text)
            .font(Theme.Typeface.caption.weight(tone == .plain && !solid ? .regular : .semibold))
            // 채운 칩에서는 `onFill`이 아니라 카드 색을 쓴다. 다크 모드의 진한 톤은 밝아서 흰 글자의 대비가 3:1보다
            // 낮았다.
            .foregroundStyle(
                solid ? Theme.Palette.card : tone == .accent ? accent.ink : tone == .plain ? Theme.Palette.textSecondary : tone.foreground
            )
            .lineLimit(1)
            .fixedSize()
            .padding(Theme.Inset.tag)
            .background(solid ? tone.foreground : tone == .accent ? accent.tint : tone.fill, in: .capsule)
    }
}

struct Avatar: View {
    let name: String
    let id: UUID
    var size: CGFloat = 26

    var body: some View {
        let colors = CourseAccent.presets.filter { $0.name != CourseColor.neutral }
        let accent = colors[Int(id.uuid.0) % colors.count].accent
        Circle().fill(accent.color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(accent.ink)
            }
    }
}

struct CourseMark: View {
    let icon: String?
    let color: Color
    var font: Font = Theme.Glyph.line
    var filled = false
    var duotone = false
    var inline = false

    static let defaultIcon = "book.closed"

    var body: some View {
        if inline {
            Image(systemName: icon ?? Self.defaultIcon).foregroundStyle(color)
        } else {
            LineIcon(symbol: icon ?? Self.defaultIcon, font: font, filled: filled, duotone: duotone).foregroundStyle(color)
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

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(Theme.Typeface.label).monospaced()
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, Theme.Space.tight).padding(.vertical, Theme.Space.xxs)
            .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.small))
    }
}

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
        contentTransition(.numericText()).animation(Theme.Motion.settle, value: value)
    }
}

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
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
}
