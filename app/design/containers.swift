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

/// Settings-style row: label (and optional detail) on the left, the control on the right.
struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    var last = false
    @ViewBuilder var control: Control

    var body: some View {
        CardRow(last: last) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(label)
                if let detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
            }
            Spacer(minLength: Theme.Space.m)
            control
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
    @ViewBuilder var rows: Rows
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(title).font(Theme.Typeface.columnTitle)
            if carded { Card { rows } } else { rows }
            if let note { Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).padding(.horizontal, Theme.Space.m) }
            HStack {
                if let deleteTitle, let onDelete {
                    Button(deleteTitle, role: .destructive, action: onDelete).buttonStyle(.pointing(.bordered)).foregroundStyle(Theme.Palette.danger)
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
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
