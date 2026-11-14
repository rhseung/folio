import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct MaterialLinksEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: MaterialsModel
    let materialId: UUID

    static let width: CGFloat = 560

    var body: some View {
        SheetForm(
            title: model.linksTitle(materialId), confirm: String(localized: .commonDone), carded: false, width: Self.width,
            cancellable: false
        ) {
            links
        } onConfirm: {
            dismiss()
        }
        .task(id: materialId) { await model.loadPageCount(materialId) }
        .onAppear { if let m = model.materials.first(where: { $0.id == materialId }) { model.startRenaming(m) } }
    }

    private func name(_ m: FolioDomain.Material) -> some View {
        let new = model.renamed(m)
        return Block(String(localized: .materialsRenameField), note: new ?? model.renameMessage(m)) {
            Card {
                CardRow(last: true) {
                    InlineField(String(localized: .materialsRenameField), text: $model.newName)
                        .onSubmit { model.rename(m) }
                    Button(.materialsRenameConfirm) { model.rename(m) }
                        .buttonStyle(.ghost)
                        .disabled(new == nil)
                }
            }
        }
    }

    @ViewBuilder private var links: some View {
        let unitIds = model.unitIds(of: materialId)
        let viaSessions = model.unitsViaSessions(of: materialId)
        let sessions = model.sessions(linking: materialId)
        let units = model.units
        let exams = model.exams
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let m = model.materials.first(where: { $0.id == materialId }) { name(m) }
                if model.isLecture(materialId) {
                    LectureProgressBlock(workspace: model.workspace, course: model.course.id, material: materialId) { dismiss() }
                }
                Block(String(localized: .materialsLinksSessions)) {
                    Card {
                        if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoSessions)) } }
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            let link = s.materials.first { $0.materialId == materialId }
                            CardRow(last: i == sessions.count - 1) {
                                CheckCircle(on: link != nil) { model.link(materialId, session: s.id, linked: link == nil) }
                                Text(model.sessionTitle(s)).lineLimit(1).layoutPriority(1)
                                Spacer(minLength: Theme.Space.s)
                                if let link {
                                    PageRangeField(
                                        range: link.pageRange, pages: model.pageCounts[materialId],
                                        taught: model.taught(materialId, besides: s.id), seen: model.seen(materialId, in: s),
                                        sections: model.sections(materialId), compact: true
                                    ) {
                                        model.setPages(materialId, session: s.id, $0)
                                    }
                                }
                            }
                        }
                    }
                }
                Block(String(localized: .materialsLinksUnits)) {
                    Card {
                        if units.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoUnits)) } }
                        ForEach(Array(units.enumerated()), id: \.element.unit.id) { i, row in
                            let u = row.unit
                            let linked = unitIds.contains(u.id)
                            CardRow(last: i == units.count - 1) {
                                CheckCircle(on: linked) { model.link(materialId, unit: u.id, linked: !linked) }
                                    .padding(.leading, CGFloat(row.depth) * Theme.Space.l)
                                Text(u.title).lineLimit(1)
                                Spacer()
                                if !linked, let pages = model.splitPages(of: materialId, unit: u.id) {
                                    Text(pages).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                } else if !linked && viaSessions.contains(u.id) {
                                    Text(.commonViaSessions).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                }
                Block(String(localized: .materialsLinksExams)) {
                    Card {
                        if exams.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoExams)) } }
                        ForEach(Array(exams.enumerated()), id: \.element.id) { i, exam in
                            let routes = model.routes(of: materialId, to: exam)
                            let linked = routes.contains(.direct)
                            CardRow(last: i == exams.count - 1) {
                                CheckCircle(on: linked) { model.link(materialId, exam: exam.id, linked: !linked) }
                                Text(exam.title).lineLimit(1)
                                Spacer()
                                if routes.contains(.folder) {
                                    Text(.materialsLinksInFolder).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .overflowFade(.vertical)
        .frame(height: 520)
    }
}
