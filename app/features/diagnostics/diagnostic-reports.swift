import FolioDomain
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticReports: View {
    @State private var model: DiagnosticsModel

    init(workspace: Workspace) { _model = State(initialValue: DiagnosticsModel(workspace: workspace)) }

    var body: some View {
        Block(
            title: String(localized: .diagnosticsTitle), note: model.note,
            trailing: {
                Button(.diagnosticsExport) { model.export() }
                    .buttonStyle(.ghost).contentShape(TouchTarget())
                    .disabled(model.isEmpty)
                Button(.diagnosticsDeleteAll) { model.confirmingDelete = true }
                    .buttonStyle(.ghost).contentShape(TouchTarget())
                    .disabled(model.isEmpty)
            },
            content: {
                Card {
                    let rows = model.rows
                    if rows.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .diagnosticsEmpty)) } }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        CardRow(last: i == rows.count - 1) { DiagnosticRow(row: row) }
                    }
                }
            }
        )
        .fileExporter(
            isPresented: Binding(get: { model.exporting != nil }, set: { if !$0 { model.exporting = nil } }),
            document: model.exporting, contentType: .json, defaultFilename: model.exportName
        ) { result in
            if case .success = result { model.exported() }
        }
        .confirmationDialog(String(localized: .diagnosticsDeleteTitle), isPresented: $model.confirmingDelete, titleVisibility: .visible) {
            Button(String(localized: .commonDelete), role: .destructive) { model.removeAll() }
            Button(String(localized: .commonCancel), role: .cancel) {}
        }
        // 목록을 본 뒤에만 본 것으로 표시해야, 페이지에 있는 동안 새 보고 표시가 남는다.
        .onDisappear(perform: model.markSeen)
    }
}

private struct DiagnosticRow: View {
    let row: DiagnosticsModel.Row

    var body: some View {
        Image(systemName: row.kind.symbol).foregroundStyle(row.kind.tone.foreground).frame(width: Theme.Size.tile)
            .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                Text(row.title).lineLimit(1)
                if row.isNew { Badge(String(localized: .diagnosticsNew), tone: .info) }
            }
            if let detail = row.detail {
                Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        Spacer(minLength: Theme.Space.s)
        Text(row.when).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).fixedSize()
    }
}
