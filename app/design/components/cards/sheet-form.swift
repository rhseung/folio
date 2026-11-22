import FolioDomain
import SwiftUI

struct SheetForm<Rows: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirm: String
    var isDisabled = false
    var note: String?
    var carded = true
    var width: CGFloat = 460
    var deleteTitle: String?
    var onDelete: (() -> Void)?
    var mark: CourseMark?
    var cancel: String?
    var step: String?
    var cancellable = true
    // 시트가 아니라 화면에 둔 폼(풀기 고르기)은 닫을 시트가 없으므로 취소가 이 동작을 부르고, 좁은 칸에서는 폭을 줄인다.
    var onCancel: (() -> Void)?
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
                if cancellable {
                    Button(cancel ?? String(localized: .commonCancel)) { if let onCancel { onCancel() } else { dismiss() } }
                        .keyboardShortcut(.cancelAction)
                }
                Button(confirm, action: onConfirm).buttonStyle(.prominent).keyboardShortcut(.defaultAction).disabled(isDisabled)
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
        .frame(width: onCancel == nil ? width : nil)
        .frame(maxWidth: onCancel == nil ? nil : width)
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
