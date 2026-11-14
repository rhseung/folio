import FolioDomain
import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    var clipped = false
    @ViewBuilder var content: Content

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        // 요청할 때만 자른다. 모든 카드를 자르면 행이 가장자리 밖에 그리는 것이 잘렸다.
        Group { if clipped { rows.clipShape(.rect(cornerRadius: Theme.Radius.card)) } else { rows } }
            .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }
}

struct NoticeCard<Trailing: View, Rows: View>: View {
    let title: String
    var detail: String?
    var systemImage = "exclamationmark.bubble.fill"
    var informs = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var rows: Rows

    var body: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) {
                    words(detailIdeal: 0)
                    Spacer(minLength: Theme.Space.s)
                    action
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    words(detailIdeal: nil)
                    action.padding(.leading, Theme.Space.m + Theme.Size.tile)
                }
            }
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            .background(informs ? Theme.Palette.infoFill : Theme.Palette.warningBanner, in: .rect(cornerRadius: Theme.Radius.card))
            rows
        }
    }
}

extension NoticeCard {
    func words(detailIdeal: CGFloat?) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage).foregroundStyle(informs ? Theme.Palette.info : Theme.Palette.warning).font(
                Theme.Typeface.bodyStrong
            )
            .frame(width: Theme.Size.tile)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                if let detail {
                    Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(idealWidth: detailIdeal, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    var action: some View { trailing.lineLimit(1).fixedSize() }
}

extension NoticeCard where Rows == EmptyView {
    init(title: String, detail: String? = nil, systemImage: String = "exclamationmark.bubble.fill", @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, systemImage: systemImage, trailing: trailing, rows: { EmptyView() })
    }
}

struct CardRow<Content: View>: View {
    var last = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) { content }
                .padding(Theme.Inset.row)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            if !last { Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l) }
        }
    }
}

struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    var device = false
    var warns = false
    var last = false
    @ViewBuilder var control: Control

    var body: some View {
        CardRow(last: last) {
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.tight) {
                        Text(label).lineLimit(1)
                        if device { DeviceTag() }
                    }
                    if let detail {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(
                            warns ? Theme.Palette.warning : Theme.Palette.textTertiary)
                    }
                }
            } control: {
                control
            }
        }
    }
}

struct DeviceTag: View {
    var body: some View {
        Text(.designThisDevice)
            .font(Theme.Typeface.label)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.tight)
            .padding(.vertical, Theme.Space.xxs)
            .overlay(Capsule().strokeBorder(Theme.Palette.line))
            .fixedSize()
    }
}

struct DisclosureRow<Rows: View>: View {
    let label: String
    @Binding var isOpen: Bool
    var last = false
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { isOpen.toggle() }
            } label: {
                CardRow(last: last && !isOpen) {
                    Text(label).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "chevron.right")
                        .font(Theme.Glyph.small)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .accessibilityValue(Text(isOpen ? .designExpanded : .designCollapsed))
            if isOpen {
                VStack(alignment: .leading, spacing: 0) { rows }
                    .padding(.leading, Theme.Space.l)
                    .background(Theme.Palette.fill.opacity(Theme.Opacity.folded))
            }
        }
    }
}

struct FoldingRow<Title: View, Control: View>: View {
    static var labelRoom: CGFloat { 120 }

    @ViewBuilder var title: Title
    @ViewBuilder var control: Control

    var body: some View {
        // `ViewThatFits`는 ideal 폭으로 판단하는데, 이름의 ideal 폭은 한 줄 전체라서 설명이 긴 행은 넓은 창에서도
        // 접혔다. 그래서 이름의 ideal 폭을 필요한 폭으로 고정해 컨트롤의 폭만 판단에 들어가게 한다.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) {
                title.frame(idealWidth: Self.labelRoom, alignment: .leading)
                Spacer(minLength: Theme.Space.m)
                control
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Space.m) { control }
            }
        }
    }
}

// 폭을 재서 플래그로 두지 않는다. 플래그는 넓은 상태로 시작하므로, 처음 나란히 그릴 때 두 블록의 최소 폭만큼 좁은 칸을
// 밀어냈다.
struct Fold<Content: View>: View {
    let wideFrom: CGFloat
    var spacing: CGFloat = Theme.Space.xl
    var stackSpacing: CGFloat = Theme.Space.section
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) { content }
                .frame(idealWidth: wideFrom)
            VStack(alignment: .leading, spacing: stackSpacing) { content }
        }
    }
}

struct FormTextArea: View {
    let label: String
    var detail: String?
    @Binding var text: String
    @Environment(\.textAreaRoom) private var textAreaRoom

    private static var around: CGFloat { Theme.Space.l + Theme.Space.s + 2 * Theme.Space.m }

    var body: some View {
        Block(label, note: detail) {
            Card(padding: Theme.Space.m) {
                GrowingTextEditor(text: $text, room: textAreaRoom.map { $0 - Self.around })
            }
        }
    }
}

struct InlineField: View {
    let prompt: String
    @Binding var text: String

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        self._text = text
    }

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 280)
    }
}

struct SheetForm<Rows: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirm: String
    var disabled = false
    var note: String?
    var carded = true
    var width: CGFloat = 460
    var deleteTitle: String?
    var onDelete: (() -> Void)?
    var mark: CourseMark?
    var cancel: String?
    var step: String?
    var cancellable = true
    @ViewBuilder var rows: Rows
    let onConfirm: () -> Void
    @Environment(\.sheetRoom) private var room
    @State private var rowsHeight: CGFloat = 0
    @State private var chrome: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                if let mark { mark }
                Text(title).font(Theme.Typeface.columnTitle).lineLimit(1)
                if let step {
                    Spacer(minLength: Theme.Space.s)
                    Text(step).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit().fixedSize()
                }
            }
            if let room {
                let viewport = max(room - chrome, Self.leastRows)
                ScrollView {
                    form.onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        rowsHeight = $0
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .overflowFade(.vertical)
                .frame(minHeight: 0, idealHeight: min(rowsHeight, viewport), maxHeight: min(rowsHeight, viewport))
                .environment(\.textAreaRoom, viewport)
            } else {
                form
            }
            if let note {
                Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).padding(.horizontal, Theme.Space.m)
            }
            HStack {
                if let deleteTitle, let onDelete {
                    Button(deleteTitle, role: .destructive, action: onDelete).buttonStyle(.pointing(.bordered)).foregroundStyle(
                        Theme.Palette.danger)
                }
                Spacer()
                if cancellable { Button(cancel ?? String(localized: .commonCancel)) { dismiss() }.keyboardShortcut(.cancelAction) }
                Button(confirm, action: onConfirm).buttonStyle(.prominent).keyboardShortcut(.defaultAction).disabled(disabled)
            }
        }
        #if os(macOS)
        .onExitCommand(perform: cancellable ? nil : onConfirm)
        #endif
        .padding(Theme.Space.xl)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            chrome = $0 - shown
        }
        .frame(width: width)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if carded { Card { rows } } else { rows }
        }
    }

    private var shown: CGFloat { room.map { min(rowsHeight, max($0 - chrome, Self.leastRows)) } ?? rowsHeight }

    private static var leastRows: CGFloat { Theme.Size.rowHeight * 3 }
}

extension EnvironmentValues {
    @Entry var sheetRoom: CGFloat?
    @Entry var textAreaRoom: CGFloat?
}

struct EmptyCard: View {
    let symbol: String
    var tone: Tone = .plain
    let title: String
    var detail: String?

    var body: some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: symbol)
                    .font(Theme.Glyph.check)
                    .foregroundStyle(tone == .plain ? Theme.Palette.textTertiary : tone.foreground)
                    .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                    .background(
                        tone == .plain ? Theme.Palette.fill : tone.foreground.opacity(Theme.Opacity.tint),
                        in: .rect(cornerRadius: Theme.Radius.control))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                    if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        }
    }
}
