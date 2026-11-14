import FolioDomain
import SwiftUI

// PDFKit의 `PDFThumbnailView`가 아니라 여기서 그린다. `PDFThumbnailView`는 iPad에서 한 쪽만 고를 수 있고, 쪽 위나 옆에 아무것도 놓을 수 없다. 길게 누르기가 된다는 것이
// 화면에 보이지 않으므로, iPad에는 고르기를 시작하는 버튼도 쪽 위에 둔다.
struct PageStrip: View {
    let controller: PDFController
    @State private var model: PageStripModel
    @Environment(\.accent) private var accent

    init(controller: PDFController, model: PageStripModel) {
        self.controller = controller
        _model = State(initialValue: model)
    }

    static let column: CGFloat = 128
    static let lectureColumn = Theme.Size.pageThumbnail.width + Theme.Space.s * 4

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
                    // 행이 움직인 뒤에 스크롤한다. 바로 스크롤하면 열이 그 행을 아직 범위의 반대쪽 끝에 두고 있었다.
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

private struct PageStripItem: View {
    let item: StripItem
    @Bindable var model: PageStripModel
    let controller: PDFController

    var body: some View {
        StripItemFrame(item: item) {
            row(item.lead)
            if let page = item.page {
                StripPage(
                    controller: controller, page: page, picked: item.mark == .picked, box: PageStrip.box(lecture: model.isLecture),
                    ranging: model.pickingShown,
                    press: { page, extend in extend ? model.extend(to: page) : model.press(page) },
                    start: { model.start(at: $0) })
            }
            row(item.trail)
        }
    }

    @ViewBuilder private func row(_ lead: StripItem.Lead?) -> some View {
        switch lead {
        case .header(let section, let open)?:
            StripHeader(
                section: section, open: open, lit: model.fresh == section.id, help: Text(.fileViewProgressEditHelp),
                toggle: { model.toggle(section) }, edit: { model.edit(section) }
            )
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
