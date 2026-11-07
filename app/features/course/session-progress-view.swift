import FolioDomain
import SwiftUI

/// The end-of-class prompt: each lecture file the class went through, with its first and last page.
struct SessionProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionProgressModel

    init(workspace: Workspace, course: UUID, session: UUID, viewed: [SessionMaterial] = []) {
        _model = State(initialValue: SessionProgressModel(workspace: workspace, course: course, session: session, viewed: viewed))
    }

    var body: some View {
        let rows = model.rows
        SheetForm(title: model.title, confirm: String(localized: .commonSave), disabled: model.refusal != nil, note: model.note, width: 640) {
            if rows.isEmpty {
                CardRow(last: model.addable.isEmpty) { EmptyLine(String(localized: .sessionsProgressEmpty)) }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                CardRow(last: i == rows.count - 1 && model.addable.isEmpty) {
                    CheckCircle(on: row.included) { model.toggle(row.id) }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(model.name(row.id)).lineLimit(1).truncationMode(.middle)
                        let detail = model.detail(row.id)
                        if !detail.isEmpty {
                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 176, alignment: .leading)
                    .opacity(row.included ? 1 : Theme.Opacity.ended)
                    Spacer(minLength: Theme.Space.s)
                    PageRangeField(range: row.range, pages: model.pageCounts[row.id], taught: model.taught(row.id),
                                   seen: model.seen(row.id), resume: model.resume(row.id)) { model.setRange(row.id, $0) }
                        .opacity(row.included ? 1 : Theme.Opacity.ended)
                }
            }
            if !model.addable.isEmpty {
                CardRow(last: true) {
                    Menu {
                        ForEach(model.addable) { m in
                            Button((m.path as NSString).lastPathComponent) { model.add(m.id) }
                        }
                    } label: {
                        Label(.sessionsProgressAddFile, systemImage: "plus")
                    }
                    .menuStyle(.button).buttonStyle(.ghost).fixedSize()
                    Spacer()
                }
            }
        } onConfirm: {
            model.record()
            dismiss()
        }
        .task { await model.load() }
        .environment(\.accent, model.accent)
    }
}

/// Shows the prompt a stopped recording asks for, in the window it was stopped from. Every window watches the same
/// ask; the first that takes it clears it, so two windows don't both ask.
struct SessionProgressPrompt: ViewModifier {
    let workspace: Workspace
    @State private var shown: SessionProgressAsk?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: workspace.progressAsk) { _, ask in
                guard let ask, workspace.progressAsk == ask else { return }
                #if os(macOS)
                // The stop button was in the key window.
                guard active else { return }
                workspace.progressAsk = nil
                shown = ask
                #else
                workspace.progressAsk = nil
                // The recording card's popover is still going away; a sheet asked for meanwhile is dropped.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    shown = ask
                }
                #endif
            }
            .sheet(item: $shown) { ask in
                SessionProgressSheet(workspace: workspace, course: ask.course, session: ask.session, viewed: ask.viewed)
            }
    }
}

extension View {
    func sessionProgressPrompt(_ workspace: Workspace) -> some View { modifier(SessionProgressPrompt(workspace: workspace)) }
}
