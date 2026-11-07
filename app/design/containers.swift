import FolioDomain
import SwiftUI

/// White rounded card that holds rows separated by inset hairlines.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }
}

/// A banner heading a `Card` that holds the rows it's about, so the decision is made where it's announced.
/// Rows are `CardRow`s; without rows it is the banner alone.
struct NoticeCard<Trailing: View, Rows: View>: View {
    let title: String
    var detail: String?
    var systemImage = "exclamationmark.bubble.fill"
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var rows: Rows

    var body: some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: systemImage).foregroundStyle(Theme.Palette.warning).font(Theme.Typeface.bodyStrong)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.bodyStrong)
                    if let detail {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                trailing
            }
            // A row's padding and height, so the banner is never slimmer than an empty card beside it.
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            .background(Theme.Palette.warningBanner, in: .rect(cornerRadius: Theme.Radius.card))
            rows
        }
    }
}

extension NoticeCard where Rows == EmptyView {
    init(title: String, detail: String? = nil, systemImage: String = "exclamationmark.bubble.fill", @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, systemImage: systemImage, trailing: trailing, rows: { EmptyView() })
    }
}

/// One row inside a `Card`. The hairline under it starts at the text, as in system settings.
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

/// Settings-style row: label (and optional detail) on the left, the control on the right, or under the label where
/// the two don't fit on one line.
struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    var last = false
    @ViewBuilder var control: Control

    var body: some View {
        CardRow(last: last) {
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(label)
                    if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                }
            } control: {
                control
            }
        }
    }
}

/// A row's name and its control side by side, or the control under the name when the row is too narrow for both: in
/// a pane or on an iPhone a fixed-width control (a grade track) otherwise squeezed the name to nothing.
struct FoldingRow<Title: View, Control: View>: View {
    /// What the name keeps beside the control before the control moves under it.
    static var labelRoom: CGFloat { 120 }

    @ViewBuilder var title: Title
    @ViewBuilder var control: Control

    var body: some View {
        // ViewThatFits goes by ideal widths; the name's is its whole line, which would fold a row with a long
        // detail even in a full window. Its ideal is pinned to the room it needs, so only the control's width counts.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) {
                // Not stretched: a stretched name took the room a control's own text (색's "자동") needed.
                title.frame(idealWidth: Self.labelRoom, alignment: .leading)
                Spacer(minLength: Theme.Space.m)
                control
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                // Still a row: a control of several parts (a field, its unit and a switch) put each on a line of its own.
                HStack(spacing: Theme.Space.m) { control }
            }
        }
    }
}

/// Side by side from `wideFrom` points up, one under the other below it: how blocks that share a row fold in a pane
/// or on an iPhone. Not a width measured into a flag: a flag starts wide, and its first, side-by-side pass pushed a
/// narrow pane out by the pair's minimum width.
struct Fold<Content: View>: View {
    /// At least what the blocks need side by side, so they never squeeze past their own minimums.
    let wideFrom: CGFloat
    var spacing: CGFloat = Theme.Space.xl
    var stackSpacing: CGFloat = Theme.Space.section
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // The pair's ideal width is pinned to `wideFrom`: left to the blocks, whole lines of text decided instead.
            HStack(alignment: .top, spacing: spacing) { content }
                .frame(idealWidth: wideFrom)
            VStack(alignment: .leading, spacing: stackSpacing) { content }
        }
    }
}

/// Several lines of text in a form: a section of its own, the label and help as its heading and a card holding only the editor.
/// Never put it inside another card: a tall editor among single-line rows breaks their rhythm.
struct FormTextArea: View {
    let label: String
    var detail: String?
    @Binding var text: String
    var height: CGFloat = 72

    var body: some View {
        Block(label, note: detail) {
            Card(padding: Theme.Space.m) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(Theme.Typeface.body)
                    .frame(height: height)
            }
        }
    }
}

/// Wide text input inside a card row.
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

/// A sheet with a title, one card of form rows and a confirm button.
struct SheetForm<Rows: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirm: String
    var disabled = false
    var note: String?
    /// False when the rows bring their own grouped cards, for a form with sections.
    var carded = true
    var width: CGFloat = 460
    /// A destructive button at the footer's leading end, in every sheet that deletes; the sheet asks to confirm.
    var deleteTitle: String?
    var onDelete: (() -> Void)?
    /// The course's icon before the title, for a sheet about one of its classes.
    var mark: CourseMark?
    /// For a sheet that comes back later (a class's wrap-up), "나중에" rather than "취소".
    var cancel: String?
    /// Where a run through several sheets is, at the title's trailing end.
    var step: String?
    @ViewBuilder var rows: Rows
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                if let mark { mark }
                Text(title).font(Theme.Typeface.columnTitle)
                if let step {
                    Spacer(minLength: Theme.Space.s)
                    Text(step).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
            }
            if carded { Card { rows } } else { rows }
            if let note { Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).padding(.horizontal, Theme.Space.m) }
            HStack {
                if let deleteTitle, let onDelete {
                    Button(deleteTitle, role: .destructive, action: onDelete).buttonStyle(.pointing(.bordered)).foregroundStyle(Theme.Palette.danger)
                }
                Spacer()
                Button(cancel ?? String(localized: .commonCancel)) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirm, action: onConfirm).buttonStyle(.pointing(.borderedProminent)).keyboardShortcut(.defaultAction).disabled(disabled)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: width)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }
}

/// A block with nothing in it, said in one card: a glyph, what is empty, and what fills it. Shorter than the block it
/// stands for, so an empty column beside a full one doesn't hold open a tall hole.
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
                    .background(tone == .plain ? Theme.Palette.fill : tone.foreground.opacity(Theme.Opacity.tint), in: .rect(cornerRadius: Theme.Radius.control))
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.bodyStrong)
                    if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        }
    }
}
