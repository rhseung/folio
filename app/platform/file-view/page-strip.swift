import FolioDomain
import SwiftUI

/// A PDF's pages small, down the side of its file view. Pressing one goes to it. On a course's lecture file the pages
/// fall into sections, one per class that went through them, each under a one-line header that folds it; a range
/// picked on the plain pages (⇧-click on a Mac, a long press then taps on iPad) is saved as a class's progress from a
/// row at the end it was picked out to, and a header pressed changes that class's range the same way (#147). The iPad
/// also has a button over the pages that starts picking, since nothing shows that a long press does.
///
/// Drawn here rather than with PDFKit's `PDFThumbnailView`, which picks no more than one page on iPad and takes nothing
/// laid over or beside its pages.
struct PageStrip: View {
    let controller: PDFController
    @State private var model: PageStripModel
    @Environment(\.accent) private var accent

    init(controller: PDFController, workspace: Workspace, course: UUID?, material: UUID?) {
        self.controller = controller
        _model = State(initialValue: PageStripModel(workspace: workspace, course: course, material: material, pageCount: controller.pageCount))
    }

    static let column: CGFloat = 128
    /// A lecture file's column: its sections' tint reaches the column's margins and holds the pages `Space.s` in on
    /// each side, the current page's wash just filling it.
    static let lectureColumn = Theme.Size.pageThumbnail.width + Theme.Space.s * 4

    /// The box a page is fitted into: a lecture's, or what a plain column holds inside its margins.
    static func box(lecture: Bool) -> CGSize {
        lecture ? Theme.Size.pageThumbnail : CGSize(width: column - Theme.Space.s * 2, height: Theme.Size.pageThumbnail.height)
    }

    var body: some View {
        let isLecture = model.isLecture
        VStack(spacing: 0) {
            #if os(iOS)
            if isLecture { ProgressPickBar(model: model) }
            #endif
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.items) { item in
                            PageStripItem(item: item, model: model, controller: controller)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, Theme.Space.s)
                }
                .overflowFade(.vertical)
                .onChange(of: controller.page, initial: true) { _, page in proxy.scrollTo(model.itemID(showing: page + 1)) }
                .task(id: model.draftItemID) {
                    guard let id = model.draftItemID else { return }
                    // After the row has moved: scrolled to at once, the column still had it at the range's other end.
                    try? await Task.sleep(for: .seconds(0.25))
                    withAnimation(Theme.Motion.quick) { proxy.scrollTo(id) }
                }
            }
        }
        .animation(Theme.Motion.quick, value: model.items)
        .frame(width: isLecture ? Self.lectureColumn : Self.column)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: model.selection)
        #endif
        .task(id: model.fresh) {
            guard model.fresh != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { model.fresh = nil }
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.strip) { _, step in
            switch step {
            case .page(let page)?:
                model.clear()
                controller.go(to: page - 1)
            case .range(let from, let to)?:
                model.press(from)
                model.extend(to: to)
                go(to: to)
            case .edit(let page, let to)?:
                if let section = model.sections.first(where: { $0.pages.contains(page) }) { model.edit(section) }
                model.extend(to: to)
                go(to: to)
            case .choose?: model.choosing = model.onlyToday == nil
            case .save?: model.commit()
            case .remove(let page)?:
                if let section = model.sections.first(where: { $0.pages.contains(page) }) { model.remove(section) }
                go(to: page + 1)
            case nil: break
            }
        }
        #endif
    }

    #if DEBUG && os(macOS)
    /// After the row above the range is laid out, and by way of the page after it: scrolled to at once, the row pushed
    /// the page below the strip's bottom edge, and scrolled to from above, it sat under the bottom's fade.
    private func go(to page: Int) {
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            controller.go(to: page)
            try? await Task.sleep(for: .seconds(0.4))
            controller.go(to: page - 1)
        }
    }
    #endif
}

/// One page of the column, with the header, edit row or draft row heading it, or a folded section's header alone.
private struct PageStripItem: View {
    let item: StripItem
    @Bindable var model: PageStripModel
    let controller: PDFController

    var body: some View {
        StripItemFrame(item: item) {
            row(item.lead)
            if let page = item.page {
                StripPage(controller: controller, page: page, picked: item.mark == .picked, box: PageStrip.box(lecture: model.isLecture), ranging: model.pickingShown,
                          press: { page, extend in extend ? model.extend(to: page) : model.press(page) },
                          start: { model.start(at: $0) })
            }
            row(item.trail)
        }
    }

    @ViewBuilder private func row(_ lead: StripItem.Lead?) -> some View {
        switch lead {
        case .header(let section, let open)?:
            StripHeader(section: section, open: open, lit: model.fresh == section.id, help: Text(.fileViewProgressEditHelp),
                        toggle: { model.toggle(section) }, edit: { model.edit(section) })
                .contextMenu {
                    Button(.commonEdit, systemImage: "pencil") { model.edit(section) }
                    Divider()
                    Button(.fileViewProgressRemove, systemImage: "link.badge.minus", role: .destructive) {
                        withAnimation(Theme.Motion.quick) { model.remove(section) }
                    }
                    .disabled(!model.canRemove(section))
                }
        case .edit(let section)?: ProgressSaveRow(model: model, editing: section)
        case .draft?: ProgressSaveRow(model: model, editing: nil)
        case nil: EmptyView()
        }
    }
}
