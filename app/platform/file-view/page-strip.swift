import FolioDomain
import SwiftUI

/// A PDF's pages small, down the side of its file view. Pressing one goes to it. On a course's lecture file the pages
/// fall into sections, one per class that went through them, each under a one-line header that folds it; a range
/// picked on the plain pages (⇧-click on a Mac, a long press then taps on iPad) is saved as a class's progress from a
/// row at the end it was picked out to, and a header pressed changes that class's range the same way (#147). The iPad also has a button over
/// the pages that starts picking, since nothing shows that a long press does.
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
        let picks = model.picks
        VStack(spacing: 0) {
            #if os(iOS)
            if picks { PickBar(model: model) }
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
        .frame(width: picks ? Self.lectureColumn : Self.column)
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
            lead(item.lead)
            if let page = item.page {
                StripPage(controller: controller, page: page, picked: item.mark == .picked, box: PageStrip.box(lecture: model.picks), ranging: model.pickingShown,
                          press: { page, extend in extend ? model.extend(to: page) : model.press(page) },
                          start: { model.start(at: $0) })
            }
            lead(item.trail)
        }
    }

    @ViewBuilder private func lead(_ lead: StripItem.Lead?) -> some View {
        switch lead {
        case .header(let section, let open)?:
            StripHeader(section: section, open: open, lit: model.fresh == section.id, help: Text(.fileViewProgressPickHelp),
                        toggle: { model.toggle(section) }, edit: { model.edit(section) })
                .contextMenu {
                    Button(.commonEdit, systemImage: "pencil") { model.edit(section) }
                    Divider()
                    Button(.fileViewProgressRemove, systemImage: "link.badge.minus", role: .destructive) {
                        withAnimation(Theme.Motion.quick) { model.remove(section) }
                    }
                    .disabled(!model.canRemove(section))
                }
        case .edit(let section)?: SaveRow(model: model, editing: section)
        case .draft?: SaveRow(model: model, editing: nil)
        case nil: EmptyView()
        }
    }
}

#if os(iOS)
/// A touch screen's visible way into picking a range, over the pages: a long press does the same, but nothing says so
/// there, and the Mac's ⇧-click has no finger to match. While it is on, a line says what the next tap does.
private struct PickBar: View {
    let model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        let on = model.pickingShown
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Button { withAnimation(Theme.Motion.quick) { model.togglePicking() } } label: {
                Label(String(localized: .fileViewProgressPick), systemImage: "rectangle.stack.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s)
                    .background(on ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                    .contentShape(.rect)
            }
            .buttonStyle(.ghost)
            .tint(accent.ink)
            .accessibilityAddTraits(on ? .isSelected : [])
            if on {
                Text(model.selection == nil ? .fileViewProgressPickFirst : .fileViewProgressPickEnd)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, Theme.Space.s)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.s)
    }
}
#endif

/// The row a range is saved from: at a new range's picked end, which class it was; in place of a section's header, its range
/// changed. Saving is `material link`, the same action as the wrap-up's.
private struct SaveRow: View {
    @Bindable var model: PageStripModel
    let editing: StripSection?
    @Environment(\.accent) private var accent

    var body: some View {
        let today = model.onlyToday
        StripEditRow(kind: editing == nil ? .new : .held, range: model.selectionLabel, confirm: String(localized: .commonSave),
                     canConfirm: model.canSave, refusal: model.refusal, cancel: { model.clear() }, commit: { model.commit() }) {
            Group {
                if let editing {
                    Text(editing.title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.text)
                } else if let today {
                    Text(today.day).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                    Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                } else {
                    Text(.fileViewProgressNew).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                }
            }
            .fixedSize()
        } extra: {
            if editing == nil, today == nil { classMenu }
            if editing != nil { removeButton }
        }
    }

    /// In the row, not only the header's menu: a touch screen has nothing that shows a long press opens one.
    private var removeButton: some View {
        Button(role: .destructive) { withAnimation(Theme.Motion.quick) { model.remove() } } label: {
            Label(String(localized: .fileViewProgressRemove), systemImage: "link.badge.minus")
                #if os(iOS)
                .frame(minHeight: Theme.Size.touchTarget)
                .contentShape(.rect)
                #endif
        }
        .buttonStyle(.ghost)
        .controlSize(.small)
        .disabled(!model.canRemove)
    }

    /// Opens to the trailing side, over the page rather than the thumbnails the range was picked on.
    private var classMenu: some View {
        Button { model.choosing = true } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(model.chosenChoice?.day ?? String(localized: .fileViewProgressNoClass)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pointing(.bordered))
        .controlSize(.small)
        .disabled(model.choices.isEmpty)
        .popover(isPresented: $model.choosing, arrowEdge: .trailing) { ProgressClassPicker(model: model) }
    }
}

/// Which class a new range was: the classes held so far with no pages of this file yet, today's picked first.
private struct ProgressClassPicker: View {
    @Bindable var model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.fileViewProgressPickClass).font(Theme.Typeface.sectionTitle)
                if let label = model.selectionLabel {
                    Text(label).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs)
            Divider().padding(.vertical, Theme.Space.xxs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.choices) { choice in row(choice) }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .overflowFade(.vertical)
        }
        .padding(Theme.Space.tight)
        .frame(width: 240)
    }

    private func row(_ choice: PageStripModel.Choice) -> some View {
        let picked = model.chosen == choice.id
        return Button {
            model.chosen = choice.id
            model.choosing = false
        } label: {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "checkmark").font(Theme.Glyph.small).opacity(picked ? 1 : 0)
                Text(choice.title).lineLimit(1)
                if choice.today {
                    Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(picked ? accent.ink : Theme.Palette.text)
            .padding(Theme.Inset.listRow)
            .background(picked ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }
}

/// One page small, with its number under it; on a soft rounded wash while the PDF is on it, as Preview marks it, and
/// ringed in the course's colour while it is in a range being picked. The wash is grey, not the course's tint, so a
/// current page that is also picked still reads as both, and neither looks like the save row above a range.
struct PageThumbnail: View {
    let thumbnails: PageThumbnails
    let page: Int
    let current: Bool
    var picked = false
    let box: CGSize
    @State private var image: CGImage?
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Theme.Palette.fill
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(picked ? accent.color : Theme.Palette.lineSoft, lineWidth: picked ? 2 : 1))
            // Every page in a slot as tall as the box, so a column of wide slides doesn't shift as their images come in.
            .frame(height: box.height)
            Text("\(page)").font(picked || current ? Theme.Typeface.label : Theme.Typeface.label.weight(.regular)).monospacedDigit()
                .foregroundStyle(picked ? accent.ink : current ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Space.s)
        .background {
            // Sideways the wash reaches into the column's margins rather than padding the page in, so a strip of fixed
            // width keeps its pages as wide as they were. Its corner is the page's plus the reach, to run alongside it, and
            // a class's tint's, to sit in it as one shape.
            if current {
                RoundedRectangle(cornerRadius: Theme.Radius.strip)
                    .fill(Theme.Palette.currentPage)
                    .padding(.horizontal, -Theme.Space.s)
            }
        }
        .task(id: page) { image = await thumbnails.image(page) }
    }

    /// The page fitted into the box, so its ring and corners hug it: a wide slide comes out shorter, a portrait page
    /// narrower. Until it is drawn, the whole box.
    private var size: CGSize {
        guard let image, image.width > 0, image.height > 0 else { return box }
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        return CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
    }
}
