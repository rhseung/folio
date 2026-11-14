import FolioDomain
import FolioStorage
import SwiftUI

struct NoteLinkMenu: View {
    let model: NoteEditorModel

    var body: some View {
        let meta = model.meta
        let current = model.currentLink
        func item(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) { if on { Label(title, systemImage: "checkmark") } else { Text(title) } }
        }
        return Menu {
            ForEach([NoteKind.rough, .review], id: \.self) { kind in
                Menu(String(localized: .notesLinkAsKind(kind.label))) {
                    ForEach(model.linkSessions(kind)) { s in
                        item(model.sessionName(s), on: model.isLinked(s, as: kind)) { model.pick(s.id, as: kind) }
                    }
                }
            }
            Menu(String(localized: .notesLinkAsExam)) {
                ForEach(model.linkExams) { e in
                    item(e.title, on: meta.kind == .examSummary && meta.examId == e.id) { model.relink(.examSummary, exam: e.id) }
                }
            }
            Menu(String(localized: .notesLinkAsUnit)) {
                ForEach(model.outline, id: \.unit.id) { u, depth in
                    item(String(repeating: "   ", count: depth) + u.title, on: meta.kind == .unit && meta.unitIds.contains(u.id)) {
                        model.toggleUnit(u.id)
                    }
                }
            }
            item(String(localized: .notesLinkAsFree), on: meta.kind == .free) { model.relink(.free) }
        } label: {
            Label(current, systemImage: "link")
        }
        .help(Text(.notesLinkHelp(current)))
    }
}
